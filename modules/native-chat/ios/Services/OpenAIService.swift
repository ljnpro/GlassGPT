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
    case thinkingStarted          // Signals UI to show thinking indicator
    case thinkingFinished         // Signals UI to collapse thinking
    case completed(String, String?) // (fullText, fullThinking?) — final safety net
    case error(OpenAIServiceError)
}

// MARK: - Non-streaming result

struct NonStreamingResult: Sendable {
    let text: String
    let thinking: String?
}

// MARK: - Errors

enum OpenAIServiceError: Error, Sendable, LocalizedError {
    case noAPIKey
    case invalidURL
    case httpError(Int, String)
    case requestFailed(String)
    case streamParsingError
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Please add it in Settings."
        case .invalidURL: return "Invalid API URL."
        case .httpError(let code, let msg): return "API error (\(code)): \(msg)"
        case .requestFailed(let msg): return msg
        case .streamParsingError: return "Failed to parse the streaming response."
        case .cancelled: return "Request was cancelled."
        }
    }
}

// MARK: - Codable Helpers

private struct DeltaPayload: Decodable, Sendable {
    let delta: String
}

// MARK: - OpenAI Service

@MainActor
final class OpenAIService {

    private let baseURL = "https://api.openai.com/v1/responses"
    private let maxStreamRetries = 2
    private var currentTask: Task<Void, Never>?

    // MARK: - Stream Chat (primary entry point)

    /// Streams chat events. If streaming fails before any output is emitted,
    /// automatically falls back to a non-streaming request so the response is never lost.
    func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) -> AsyncStream<StreamEvent> {
        currentTask?.cancel()

        let capturedBaseURL = baseURL
        let capturedMaxRetries = maxStreamRetries

        // Capture weak self before entering closures to avoid
        // "reference to captured var 'self' in concurrently-executing code"
        weak var weakSelf = self

        return AsyncStream { continuation in
            let task = Task.detached {
                // --- Attempt streaming first ---
                let streamSuccess = await Self.attemptStreaming(
                    baseURL: capturedBaseURL,
                    apiKey: apiKey,
                    messages: messages,
                    model: model,
                    reasoningEffort: reasoningEffort,
                    maxRetries: capturedMaxRetries,
                    continuation: continuation
                )

                if streamSuccess { return }

                // --- Streaming failed with no output → fallback to non-streaming ---
                #if DEBUG
                print("[OpenAIService] Streaming failed, falling back to non-streaming request")
                #endif

                do {
                    try Task.checkCancellation()
                    let result = try await Self.nonStreamingRequest(
                        baseURL: capturedBaseURL,
                        apiKey: apiKey,
                        messages: messages,
                        model: model,
                        reasoningEffort: reasoningEffort
                    )

                    // Emit the full result as a single completed event
                    if let thinking = result.thinking, !thinking.isEmpty {
                        continuation.yield(.thinkingStarted)
                        continuation.yield(.thinkingDelta(thinking))
                        continuation.yield(.thinkingFinished)
                    }
                    continuation.yield(.completed(result.text, result.thinking))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.error(.requestFailed(error.localizedDescription)))
                    continuation.finish()
                }
            }

            Task { @MainActor in
                weakSelf?.currentTask = task
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { @MainActor in
                    weakSelf?.currentTask = nil
                }
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

        let body: [String: Any] = [
            "model": "gpt-5.4",
            "instructions": "Generate a short, concise title (max 6 words) for the following conversation. Return only the title text, nothing else.",
            "input": [
                [
                    "role": "user",
                    "content": conversationPreview
                ]
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

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let outputText = json["output_text"] as? String {
            return outputText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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

    // MARK: - Streaming Implementation

    /// Attempts streaming. Returns `true` if streaming succeeded (emitted output),
    /// `false` if it failed before emitting any output (caller should fallback).
    private nonisolated static func attemptStreaming(
        baseURL: String,
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        maxRetries: Int,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async -> Bool {
        var emittedAnyOutput = false
        var thinkingStartedEmitted = false

        for attempt in 0...maxRetries {
            if attempt > 0 && emittedAnyOutput { break }

            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 500_000_000 // 0.5s, 1s
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                try Task.checkCancellation()

                let request = try buildStreamRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: messages,
                    model: model,
                    reasoningEffort: reasoningEffort
                )

                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    if attempt == maxRetries { return false }
                    continue
                }

                // Non-retryable HTTP errors → report immediately
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    var errorBody = ""
                    for try await line in bytes.lines { errorBody += line }
                    continuation.yield(.error(.httpError(httpResponse.statusCode, "Authentication failed. Check your API key.")))
                    continuation.finish()
                    return true // Don't fallback, auth error is definitive
                }

                if httpResponse.statusCode == 429 {
                    if attempt < maxRetries { continue }
                    continuation.yield(.error(.httpError(429, "Rate limited. Please wait and try again.")))
                    continuation.finish()
                    return true
                }

                if httpResponse.statusCode >= 400 {
                    var errorBody = ""
                    for try await line in bytes.lines { errorBody += line }

                    // Server errors are retryable
                    if httpResponse.statusCode >= 500 && attempt < maxRetries { continue }

                    // 4xx client errors → report and don't fallback
                    if httpResponse.statusCode < 500 {
                        continuation.yield(.error(.httpError(httpResponse.statusCode, String(errorBody.prefix(500)))))
                        continuation.finish()
                        return true
                    }

                    // Last retry for 5xx → let fallback handle it
                    return false
                }

                // --- Parse SSE stream ---
                var currentEventType = ""
                var dataBuffer = ""
                var sawCompleted = false
                var accumulatedText = ""
                var accumulatedThinking = ""

                for try await line in bytes.lines {
                    try Task.checkCancellation()

                    if line.isEmpty {
                        if !currentEventType.isEmpty && !dataBuffer.isEmpty {
                            let result = processSSEEvent(
                                currentEventType,
                                payload: dataBuffer,
                                emittedAnyOutput: &emittedAnyOutput,
                                thinkingStartedEmitted: &thinkingStartedEmitted,
                                accumulatedText: &accumulatedText,
                                accumulatedThinking: &accumulatedThinking,
                                continuation: continuation
                            )
                            if result == .finished {
                                sawCompleted = true
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
                        if !dataBuffer.isEmpty { dataBuffer += "\n" }
                        dataBuffer += String(line.dropFirst(6))
                    } else if line == "data:" {
                        if !dataBuffer.isEmpty { dataBuffer += "\n" }
                    }
                }

                // Process any remaining buffered event
                if !sawCompleted && !currentEventType.isEmpty && !dataBuffer.isEmpty {
                    let result = processSSEEvent(
                        currentEventType,
                        payload: dataBuffer,
                        emittedAnyOutput: &emittedAnyOutput,
                        thinkingStartedEmitted: &thinkingStartedEmitted,
                        accumulatedText: &accumulatedText,
                        accumulatedThinking: &accumulatedThinking,
                        continuation: continuation
                    )
                    if result == .finished { sawCompleted = true }
                }

                if sawCompleted || emittedAnyOutput {
                    // Always emit a completed event with accumulated text as safety net
                    let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
                    if thinkingStartedEmitted {
                        continuation.yield(.thinkingFinished)
                    }
                    continuation.yield(.completed(accumulatedText, thinking))
                    continuation.finish()
                    return true
                }

                // Stream ended with no output — retry or fallback
                if attempt == maxRetries { return false }

            } catch is CancellationError {
                continuation.finish()
                return true
            } catch {
                if emittedAnyOutput {
                    // We already emitted some output, finish with what we have
                    continuation.yield(.completed("", nil))
                    continuation.finish()
                    return true
                }
                if attempt == maxRetries { return false }
            }
        }

        return false
    }

    // MARK: - SSE Event Processing

    private enum SSEResult {
        case continued
        case finished
    }

    private nonisolated static func processSSEEvent(
        _ eventType: String,
        payload: String,
        emittedAnyOutput: inout Bool,
        thinkingStartedEmitted: inout Bool,
        accumulatedText: inout String,
        accumulatedThinking: inout String,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEResult {
        // Terminal sentinel
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return .finished
        }

        switch eventType {

        // --- Text output deltas ---
        case "response.output_text.delta":
            guard let data = payload.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(DeltaPayload.self, from: data) else {
                return .continued
            }
            emittedAnyOutput = true
            accumulatedText += parsed.delta
            continuation.yield(.textDelta(parsed.delta))
            return .continued

        // --- Text output done (full text) ---
        case "response.output_text.done":
            // This contains the full text; we use it as a safety check
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fullText = json["text"] as? String {
                // If our accumulated text is shorter, use the full text
                if fullText.count > accumulatedText.count {
                    accumulatedText = fullText
                }
            }
            emittedAnyOutput = true
            return .continued

        // --- Reasoning/thinking deltas ---
        case "response.reasoning_summary_text.delta",
             "response.reasoning.delta":
            guard let data = payload.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(DeltaPayload.self, from: data) else {
                return .continued
            }
            if !thinkingStartedEmitted {
                thinkingStartedEmitted = true
                continuation.yield(.thinkingStarted)
            }
            emittedAnyOutput = true
            accumulatedThinking += parsed.delta
            continuation.yield(.thinkingDelta(parsed.delta))
            return .continued

        // --- Reasoning summary done ---
        case "response.reasoning_summary_text.done",
             "response.reasoning_summary_part.done":
            return .continued

        // --- Lifecycle events ---
        case "response.completed":
            // Extract output_text from the full response object if available
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseObj = json["response"] as? [String: Any],
               let outputText = responseObj["output_text"] as? String {
                if outputText.count > accumulatedText.count {
                    accumulatedText = outputText
                }
                emittedAnyOutput = true
            }
            return .finished

        case "response.failed":
            // Try to extract error message
            var errorMsg = "Response generation failed"
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseObj = json["response"] as? [String: Any],
               let errorObj = responseObj["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                errorMsg = message
            }
            continuation.yield(.error(.requestFailed(errorMsg)))
            return .finished

        case "response.incomplete":
            // Incomplete but may have partial output — treat as finished
            return .finished

        case "error":
            var errorMsg = payload
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                errorMsg = message
            }
            continuation.yield(.error(.requestFailed(errorMsg)))
            return .finished

        // --- Events we can safely ignore ---
        case "response.created",
             "response.in_progress",
             "response.queued",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added":
            return .continued

        default:
            #if DEBUG
            print("[SSE] Unhandled event: \(eventType), payload prefix: \(String(payload.prefix(80)))")
            #endif
            return .continued
        }
    }

    // MARK: - Non-Streaming Fallback

    private nonisolated static func nonStreamingRequest(
        baseURL: String,
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) async throws -> NonStreamingResult {
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
            body["reasoning"] = ["effort": reasoningEffort.apiValue]
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
            throw OpenAIServiceError.streamParsingError
        }

        let outputText = json["output_text"] as? String ?? ""

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

        return NonStreamingResult(text: outputText, thinking: thinkingText)
    }

    // MARK: - Build Stream Request

    private nonisolated static func buildStreamRequest(
        baseURL: String,
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) throws -> URLRequest {
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
            "stream": true
        ]

        if reasoningEffort != .none {
            body["reasoning"] = ["effort": reasoningEffort.apiValue]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Build Input Array

    /// Builds the `input` array for the Responses API.
    /// Text-only messages use a simple string content.
    /// Multimodal messages use the content array format.
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
                // Text-only: use simple string content (preferred by API)
                input.append([
                    "role": role,
                    "content": message.content
                ])
            }
        }

        return input
    }
}
