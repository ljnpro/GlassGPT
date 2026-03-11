import Foundation

// MARK: - Sendable DTO for crossing concurrency boundaries

struct APIMessage: Sendable {
    let role: MessageRole
    let content: String
    let imageData: Data?
}

// MARK: - Stream Events

enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingStarted
    case thinkingFinished
    case completed(String, String?)   // (fullText, fullThinking?)
    case error(OpenAIServiceError)
}

// MARK: - Errors

enum OpenAIServiceError: Error, Sendable, LocalizedError {
    case noAPIKey
    case invalidURL
    case httpError(Int, String)
    case requestFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Please add it in Settings."
        case .invalidURL: return "Invalid API URL."
        case .httpError(let code, let msg): return "API error (\(code)): \(msg)"
        case .requestFailed(let msg): return msg
        case .cancelled: return "Request was cancelled."
        }
    }
}

// MARK: - OpenAI Service

@MainActor
final class OpenAIService {

    private let baseURL = "https://api.openai.com/v1/responses"
    private var currentTask: Task<Void, Never>?

    // MARK: - Stream Chat

    /// Returns an AsyncStream of StreamEvent. The caller iterates this stream on @MainActor.
    /// Internally, the network I/O runs in a detached task.
    /// If streaming fails before producing output, automatically falls back to non-streaming.
    func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) -> AsyncStream<StreamEvent> {
        // Cancel any previous stream
        currentTask?.cancel()
        currentTask = nil

        let baseURL = self.baseURL

        return AsyncStream { continuation in
            let task = Task.detached { [baseURL] in
                await Self.runStream(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: messages,
                    model: model,
                    reasoningEffort: reasoningEffort,
                    continuation: continuation
                )
            }

            // Store task reference for cancellation.
            // We use a simple approach: schedule on main actor immediately.
            let taskRef = task
            Task { @MainActor [weak self] in
                self?.currentTask = taskRef
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Cancel

    func cancelStream() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Generate Title

    func generateTitle(for conversationPreview: String, apiKey: String) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "gpt-5.4",
            "instructions": "Generate a short, concise title (max 6 words) for the following conversation. Return only the title text, nothing else.",
            "input": [
                ["role": "user", "content": conversationPreview]
            ],
            "stream": false,
            "max_output_tokens": 24
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIServiceError.requestFailed("Title generation failed")
        }

        // Extract text from output array
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = Self.extractOutputText(from: json) {
                return text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        return "New Chat"
    }

    // MARK: - Validate API Key

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Core Streaming Logic (nonisolated, runs in detached task)

    private nonisolated static func runStream(
        baseURL: String,
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async {
        // Try streaming first
        let streamResult = await attemptStreaming(
            baseURL: baseURL,
            apiKey: apiKey,
            messages: messages,
            model: model,
            reasoningEffort: reasoningEffort,
            continuation: continuation
        )

        switch streamResult {
        case .success:
            // Streaming worked, continuation already finished
            return
        case .definiteError:
            // Error already reported via continuation, already finished
            return
        case .noOutput:
            // Streaming failed without output → try non-streaming fallback
            break
        case .cancelled:
            continuation.finish()
            return
        }

        // --- Non-streaming fallback ---
        #if DEBUG
        print("[OpenAIService] Streaming produced no output, falling back to non-streaming")
        #endif

        do {
            try Task.checkCancellation()

            let (text, thinking) = try await nonStreamingFallback(
                baseURL: baseURL,
                apiKey: apiKey,
                messages: messages,
                model: model,
                reasoningEffort: reasoningEffort
            )

            // Emit thinking (if any)
            if let thinking = thinking, !thinking.isEmpty {
                continuation.yield(.thinkingStarted)
                continuation.yield(.thinkingDelta(thinking))
                continuation.yield(.thinkingFinished)
            }

            // Simulate streaming by emitting text in small chunks.
            // This ensures the user sees gradual text appearance even
            // when the real SSE stream failed and we fell back.
            let chunkSize = 8  // characters per chunk
            let delayNanos: UInt64 = 8_000_000  // ~8ms between chunks
            var offset = text.startIndex

            while offset < text.endIndex {
                try Task.checkCancellation()
                let end = text.index(offset, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                let chunk = String(text[offset..<end])
                continuation.yield(.textDelta(chunk))
                offset = end
                try? await Task.sleep(nanoseconds: delayNanos)
            }

            continuation.yield(.completed(text, thinking))
            continuation.finish()

        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.yield(.error(.requestFailed(error.localizedDescription)))
            continuation.finish()
        }
    }

    // MARK: - Stream Result

    private enum StreamResult {
        case success        // Stream completed with output
        case definiteError  // Non-retryable error reported
        case noOutput       // Stream ended without producing output
        case cancelled      // Task was cancelled
    }

    // MARK: - Attempt Streaming

    private nonisolated static func attemptStreaming(
        baseURL: String,
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async -> StreamResult {

        guard let url = URL(string: baseURL) else {
            continuation.yield(.error(.invalidURL))
            continuation.finish()
            return .definiteError
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let input = buildInputArray(messages: messages)

        var body: [String: Any] = [
            "model": model.rawValue,
            "input": input,
            "stream": true
        ]

        // Add reasoning config
        if reasoningEffort != .none {
            body["reasoning"] = [
                "effort": reasoningEffort.rawValue,
                "summary": "auto"
            ]
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            continuation.yield(.error(.requestFailed("Failed to encode request")))
            continuation.finish()
            return .definiteError
        }

        #if DEBUG
        print("[OpenAIService] Sending streaming request to \(baseURL)")
        print("[OpenAIService] Model: \(model.rawValue), Effort: \(reasoningEffort.rawValue)")
        #endif

        // Execute request
        do {
            try Task.checkCancellation()

            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .noOutput
            }

            #if DEBUG
            print("[OpenAIService] HTTP status: \(httpResponse.statusCode)")
            #endif

            // Handle HTTP errors
            if httpResponse.statusCode >= 400 {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                    if errorBody.count > 500 { break }
                }

                // Auth errors are definitive
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    continuation.yield(.error(.httpError(httpResponse.statusCode, "Authentication failed. Check your API key.")))
                    continuation.finish()
                    return .definiteError
                }

                // Rate limit
                if httpResponse.statusCode == 429 {
                    continuation.yield(.error(.httpError(429, "Rate limited. Please wait and try again.")))
                    continuation.finish()
                    return .definiteError
                }

                // Other 4xx errors
                if httpResponse.statusCode < 500 {
                    continuation.yield(.error(.httpError(httpResponse.statusCode, String(errorBody.prefix(500)))))
                    continuation.finish()
                    return .definiteError
                }

                // 5xx → try fallback
                return .noOutput
            }

            // --- Parse SSE stream ---
            var emittedAnyOutput = false
            var thinkingActive = false
            var accumulatedText = ""
            var accumulatedThinking = ""
            var currentEventType = ""
            var dataBuffer = ""

            for try await line in bytes.lines {
                try Task.checkCancellation()

                // Empty line = end of SSE event block
                if line.isEmpty {
                    if !currentEventType.isEmpty && !dataBuffer.isEmpty {
                        let eventResult = processEvent(
                            type: currentEventType,
                            data: dataBuffer,
                            emittedAnyOutput: &emittedAnyOutput,
                            thinkingActive: &thinkingActive,
                            accumulatedText: &accumulatedText,
                            accumulatedThinking: &accumulatedThinking,
                            continuation: continuation
                        )
                        if eventResult == .finished {
                            break
                        }
                    }
                    currentEventType = ""
                    dataBuffer = ""
                    continue
                }

                if line.hasPrefix("event: ") {
                    currentEventType = String(line.dropFirst(7))
                } else if line.hasPrefix("data: ") {
                    let payload = String(line.dropFirst(6))
                    if dataBuffer.isEmpty {
                        dataBuffer = payload
                    } else {
                        dataBuffer += "\n" + payload
                    }
                }
            }

            // Process any remaining buffered event
            if !currentEventType.isEmpty && !dataBuffer.isEmpty {
                _ = processEvent(
                    type: currentEventType,
                    data: dataBuffer,
                    emittedAnyOutput: &emittedAnyOutput,
                    thinkingActive: &thinkingActive,
                    accumulatedText: &accumulatedText,
                    accumulatedThinking: &accumulatedThinking,
                    continuation: continuation
                )
            }

            if emittedAnyOutput {
                // Close thinking if still open
                if thinkingActive {
                    continuation.yield(.thinkingFinished)
                }
                let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
                continuation.yield(.completed(accumulatedText, thinking))
                continuation.finish()
                return .success
            }

            // Stream ended with no output
            return .noOutput

        } catch is CancellationError {
            return .cancelled
        } catch {
            #if DEBUG
            print("[OpenAIService] Stream error: \(error.localizedDescription)")
            #endif
            return .noOutput
        }
    }

    // MARK: - Process Single SSE Event

    private enum EventResult {
        case continued
        case finished
    }

    private nonisolated static func processEvent(
        type: String,
        data: String,
        emittedAnyOutput: inout Bool,
        thinkingActive: inout Bool,
        accumulatedText: inout String,
        accumulatedThinking: inout String,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> EventResult {

        guard let jsonData = data.data(using: .utf8) else { return .continued }

        switch type {

        // --- Text output deltas ---
        case "response.output_text.delta":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? String {
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
            }
            return .continued

        // --- Text output complete ---
        case "response.output_text.done":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let fullText = json["text"] as? String {
                // Use full text if our accumulated version is shorter (safety net)
                if fullText.count > accumulatedText.count {
                    accumulatedText = fullText
                }
                emittedAnyOutput = true
            }
            return .continued

        // --- Reasoning/thinking deltas ---
        case "response.reasoning_summary_text.delta":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? String {
                if !thinkingActive {
                    thinkingActive = true
                    continuation.yield(.thinkingStarted)
                }
                emittedAnyOutput = true
                accumulatedThinking += delta
                continuation.yield(.thinkingDelta(delta))
            }
            return .continued

        // --- Reasoning summary complete ---
        case "response.reasoning_summary_text.done":
            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }
            return .continued

        // --- Response lifecycle ---
        case "response.completed":
            // Try to extract output text from the full response object
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let responseObj = json["response"] as? [String: Any] {
                if let text = extractOutputText(from: responseObj) {
                    if text.count > accumulatedText.count {
                        accumulatedText = text
                    }
                    emittedAnyOutput = true
                }
            }
            return .finished

        case "response.failed":
            var errorMsg = "Response generation failed"
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let responseObj = json["response"] as? [String: Any],
               let errorObj = responseObj["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                errorMsg = message
            }
            continuation.yield(.error(.requestFailed(errorMsg)))
            return .finished

        case "response.incomplete":
            return .finished

        case "error":
            var errorMsg = data
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = json["message"] as? String {
                errorMsg = message
            }
            continuation.yield(.error(.requestFailed(errorMsg)))
            return .finished

        // --- Ignorable lifecycle events ---
        case "response.created",
             "response.in_progress",
             "response.queued",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            return .continued

        default:
            #if DEBUG
            print("[SSE] Unhandled event: \(type)")
            #endif
            return .continued
        }
    }

    // MARK: - Non-Streaming Fallback

    private nonisolated static func nonStreamingFallback(
        baseURL: String,
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) async throws -> (String, String?) {
        guard let url = URL(string: baseURL) else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let input = buildInputArray(messages: messages)

        var body: [String: Any] = [
            "model": model.rawValue,
            "input": input,
            "stream": false
        ]

        if reasoningEffort != .none {
            body["reasoning"] = [
                "effort": reasoningEffort.rawValue,
                "summary": "auto"
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, String(errorBody.prefix(500)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIServiceError.requestFailed("Failed to parse response")
        }

        // Extract text from output array
        let outputText = extractOutputText(from: json) ?? ""

        // Extract reasoning/thinking from output items
        var thinkingText: String?
        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let type = item["type"] as? String, type == "reasoning" {
                    if let summaries = item["summary"] as? [[String: Any]] {
                        let texts = summaries.compactMap { $0["text"] as? String }
                        if !texts.isEmpty {
                            thinkingText = texts.joined(separator: "\n")
                        }
                    }
                }
            }
        }

        return (outputText, thinkingText)
    }

    // MARK: - Extract Output Text from Response JSON

    /// Extracts the assistant's text from the response JSON.
    /// The text lives in output[].content[].text for message-type items.
    private nonisolated static func extractOutputText(from json: [String: Any]) -> String? {
        // First try the convenience field (may exist in some API versions)
        if let text = json["output_text"] as? String, !text.isEmpty {
            return text
        }

        // Extract from output array
        guard let output = json["output"] as? [[String: Any]] else { return nil }

        var texts: [String] = []
        for item in output {
            guard let type = item["type"] as? String, type == "message" else { continue }
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let partType = part["type"] as? String, partType == "output_text",
                   let text = part["text"] as? String {
                    texts.append(text)
                }
            }
        }

        return texts.isEmpty ? nil : texts.joined()
    }

    // MARK: - Build Input Array

    private nonisolated static func buildInputArray(messages: [APIMessage]) -> [[String: Any]] {
        var input: [[String: Any]] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"

            if let imageData = message.imageData {
                // Multimodal: use content array
                var contentArray: [[String: Any]] = []

                if !message.content.isEmpty {
                    contentArray.append([
                        "type": "input_text",
                        "text": message.content
                    ])
                }

                let base64 = imageData.base64EncodedString()
                contentArray.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(base64)"
                ])

                input.append([
                    "role": role,
                    "content": contentArray
                ])
            } else if !message.content.isEmpty {
                // Text-only: simple string content
                input.append([
                    "role": role,
                    "content": message.content
                ])
            }
        }

        return input
    }
}
