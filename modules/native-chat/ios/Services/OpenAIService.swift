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
    case completed
    case error(OpenAIServiceError)
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
    private let maxRetries = 3
    private var currentTask: Task<Void, Never>?

    // MARK: - Stream Chat

    func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) -> AsyncStream<StreamEvent> {
        // Cancel any existing stream
        currentTask?.cancel()

        let capturedBaseURL = baseURL
        let capturedMaxRetries = maxRetries

        return AsyncStream { continuation in
            let task = Task.detached {
                var emittedAnyOutput = false

                for attempt in 0..<capturedMaxRetries {
                    // Only retry if we haven't emitted any output yet
                    if attempt > 0 && emittedAnyOutput { break }

                    if attempt > 0 {
                        let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                    }

                    do {
                        try Task.checkCancellation()

                        let request = try Self.buildStreamRequest(
                            baseURL: capturedBaseURL,
                            apiKey: apiKey,
                            messages: messages,
                            model: model,
                            reasoningEffort: reasoningEffort
                        )

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.yield(.error(.requestFailed("Invalid response")))
                            continuation.finish()
                            return
                        }

                        // Handle HTTP errors
                        if httpResponse.statusCode == 429 {
                            if !emittedAnyOutput && attempt < capturedMaxRetries - 1 { continue }
                            continuation.yield(.error(.httpError(429, "Rate limited. Please wait and try again.")))
                            continuation.finish()
                            return
                        }

                        if httpResponse.statusCode >= 400 {
                            var errorBody = ""
                            for try await line in bytes.lines { errorBody += line }

                            if httpResponse.statusCode >= 500 && !emittedAnyOutput && attempt < capturedMaxRetries - 1 {
                                continue
                            }

                            continuation.yield(.error(.httpError(httpResponse.statusCode, String(errorBody.prefix(500)))))
                            continuation.finish()
                            return
                        }

                        // Parse SSE stream
                        var currentEventType = ""
                        var dataBuffer = ""
                        var sawCompleted = false

                        for try await line in bytes.lines {
                            try Task.checkCancellation()

                            if line.isEmpty {
                                // Empty line = end of SSE event
                                if !currentEventType.isEmpty && !dataBuffer.isEmpty {
                                    let finished = Self.handleSSEEvent(
                                        currentEventType,
                                        payload: dataBuffer,
                                        emittedAnyOutput: &emittedAnyOutput,
                                        continuation: continuation
                                    )
                                    if finished { sawCompleted = true; break }
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
                            let finished = Self.handleSSEEvent(
                                currentEventType,
                                payload: dataBuffer,
                                emittedAnyOutput: &emittedAnyOutput,
                                continuation: continuation
                            )
                            if finished { sawCompleted = true }
                        }

                        if sawCompleted {
                            continuation.finish()
                            return
                        }

                        // Stream ended without completion event
                        if emittedAnyOutput {
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }

                        if attempt == capturedMaxRetries - 1 {
                            continuation.yield(.error(.streamParsingError))
                            continuation.finish()
                            return
                        }

                    } catch is CancellationError {
                        // User cancelled - finish silently, no error
                        continuation.finish()
                        return
                    } catch {
                        if attempt == capturedMaxRetries - 1 || emittedAnyOutput {
                            continuation.yield(.error(.requestFailed(error.localizedDescription)))
                            continuation.finish()
                            return
                        }
                    }
                }

                continuation.finish()
            }

            self.currentTask = task

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in
                    self?.currentTask = nil
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
            "model": ModelType.gpt5_4.rawValue,
            "instructions": "Generate a short, concise title (max 6 words) for the following conversation. Return only the title text, nothing else.",
            "input": [[
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": conversationPreview
                ]]
            ]],
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

    // MARK: - Build Request (static, no self capture)

    private static func buildStreamRequest(
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

        // Build input array - images come from message.imageData only (no duplication)
        var input: [[String: Any]] = []

        for message in messages {
            var contentArray: [[String: Any]] = []

            if !message.content.isEmpty {
                contentArray.append([
                    "type": "input_text",
                    "text": message.content
                ])
            }

            if let imageData = message.imageData {
                let base64 = imageData.base64EncodedString()
                contentArray.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(base64)"
                ])
            }

            guard !contentArray.isEmpty else { continue }

            input.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": contentArray
            ])
        }

        var body: [String: Any] = [
            "model": model.rawValue,
            "input": input,
            "stream": true
        ]

        if reasoningEffort != .none {
            body["reasoning"] = ["effort": reasoningEffort.rawValue]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - SSE Event Handler (static)

    private static func handleSSEEvent(
        _ eventType: String,
        payload: String,
        emittedAnyOutput: inout Bool,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> Bool {
        // Handle terminal sentinel
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            continuation.yield(.completed)
            return true
        }

        switch eventType {
        case "response.output_text.delta",
             "response.output_text_annotation.delta":
            guard let data = payload.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(DeltaPayload.self, from: data) else {
                return false
            }
            emittedAnyOutput = true
            continuation.yield(.textDelta(parsed.delta))
            return false

        case "response.reasoning_summary_text.delta",
             "response.reasoning.delta":
            guard let data = payload.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(DeltaPayload.self, from: data) else {
                return false
            }
            emittedAnyOutput = true
            continuation.yield(.thinkingDelta(parsed.delta))
            return false

        case "response.completed":
            continuation.yield(.completed)
            return true

        case "response.failed", "response.incomplete", "error":
            continuation.yield(.error(.requestFailed(payload)))
            return true

        default:
            #if DEBUG
            print("Unhandled SSE event type: \(eventType), payload prefix: \(String(payload.prefix(100)))")
            #endif
            return false
        }
    }
}
