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
    private var currentDelegate: SSEDelegate?

    // MARK: - Stream Chat

    func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort
    ) -> AsyncStream<StreamEvent> {
        // Cancel any previous stream
        cancelStream()

        let baseURL = self.baseURL

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let delegate = SSEDelegate(continuation: continuation)
            self.currentDelegate = delegate

            // Build the request
            guard let url = URL(string: baseURL) else {
                continuation.yield(.error(.invalidURL))
                continuation.finish()
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 300

            let input = Self.buildInputArray(messages: messages)

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
                return
            }

            #if DEBUG
            print("[OpenAI] Streaming request → \(model.rawValue), effort: \(reasoningEffort.rawValue)")
            #endif

            // Use a dedicated URLSession with the delegate for real-time chunk delivery.
            // This avoids any buffering that URLSession.shared.bytes might introduce.
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            // Disable response buffering for streaming
            config.waitsForConnectivity = true

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.session = session

            let task = session.dataTask(with: request)
            delegate.task = task
            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    // MARK: - Cancel

    func cancelStream() {
        currentDelegate?.cancel()
        currentDelegate = nil
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
            "instructions": "Generate a very short title (2-4 words max) for this conversation. Return only the title, no quotes, no punctuation at the end.",
            "input": [
                ["role": "user", "content": conversationPreview]
            ],
            "stream": false,
            "max_output_tokens": 16
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIServiceError.requestFailed("Title generation failed")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = Self.extractOutputText(from: json) {
                let cleaned = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                // Enforce max length at the model output level too
                let words = cleaned.split(separator: " ")
                if words.count > 5 {
                    return words.prefix(5).joined(separator: " ")
                }
                return cleaned
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

    // MARK: - Extract Output Text from Response JSON

    private nonisolated static func extractOutputText(from json: [String: Any]) -> String? {
        if let text = json["output_text"] as? String, !text.isEmpty {
            return text
        }

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

    nonisolated static func buildInputArray(messages: [APIMessage]) -> [[String: Any]] {
        var input: [[String: Any]] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"

            if let imageData = message.imageData {
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
                input.append([
                    "role": role,
                    "content": message.content
                ])
            }
        }

        return input
    }
}

// MARK: - SSE Delegate

/// A URLSessionDataDelegate that receives data chunks in real-time and parses
/// SSE events, yielding StreamEvents through an AsyncStream continuation.
/// This avoids the buffering issues that can occur with `URLSession.bytes`.
private final class SSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let continuation: AsyncStream<StreamEvent>.Continuation
    private let lock = NSLock()

    // SSE parser state
    private var lineBuffer = ""
    private var currentEventType = ""
    private var dataBuffer = ""

    // Accumulated content
    private var accumulatedText = ""
    private var accumulatedThinking = ""
    private var thinkingActive = false
    private var emittedAnyOutput = false
    private var finished = false

    // References for cleanup
    weak var session: URLSession?
    weak var task: URLSessionDataTask?

    init(continuation: AsyncStream<StreamEvent>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func cancel() {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()

        if !alreadyFinished {
            continuation.finish()
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            yieldErrorAndFinish(.requestFailed("Invalid response"))
            return
        }

        #if DEBUG
        print("[SSE] HTTP status: \(httpResponse.statusCode)")
        #endif

        if httpResponse.statusCode >= 400 {
            // We'll collect the error body in didReceive data
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                completionHandler(.cancel)
                yieldErrorAndFinish(.httpError(httpResponse.statusCode, "Authentication failed. Check your API key."))
                return
            }
            if httpResponse.statusCode == 429 {
                completionHandler(.cancel)
                yieldErrorAndFinish(.httpError(429, "Rate limited. Please wait and try again."))
                return
            }
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        lock.unlock()

        #if DEBUG
        if !emittedAnyOutput && chunk.count < 200 {
            print("[SSE] Chunk (\(data.count) bytes): \(chunk.prefix(200))")
        }
        #endif

        // Append to line buffer and process complete lines
        lineBuffer += chunk
        processLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()

        guard !alreadyFinished else { return }

        // Process any remaining data in the buffer
        if !lineBuffer.isEmpty {
            lineBuffer += "\n"
            processLines()
        }

        // Flush any remaining event
        if !currentEventType.isEmpty && !dataBuffer.isEmpty {
            _ = processEvent(type: currentEventType, data: dataBuffer)
        }

        if let error = error as? NSError, error.code == NSURLErrorCancelled {
            continuation.finish()
            return
        }

        if let error = error {
            #if DEBUG
            print("[SSE] Connection error: \(error.localizedDescription)")
            #endif
            if emittedAnyOutput {
                // We have partial output, complete it
                if thinkingActive {
                    continuation.yield(.thinkingFinished)
                }
                let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
                continuation.yield(.completed(accumulatedText, thinking))
            } else {
                continuation.yield(.error(.requestFailed(error.localizedDescription)))
            }
            continuation.finish()
            return
        }

        // Normal completion
        if emittedAnyOutput {
            if thinkingActive {
                continuation.yield(.thinkingFinished)
            }
            let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
            continuation.yield(.completed(accumulatedText, thinking))
        }
        continuation.finish()

        session.invalidateAndCancel()
    }

    // MARK: - SSE Line Processing

    private func processLines() {
        // Split the buffer into lines. SSE uses \n as line separator.
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            // Handle \r\n
            let trimmedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line

            if trimmedLine.isEmpty {
                // Empty line = end of SSE event block
                if !currentEventType.isEmpty && !dataBuffer.isEmpty {
                    let result = processEvent(type: currentEventType, data: dataBuffer)
                    currentEventType = ""
                    dataBuffer = ""
                    if result == .finished {
                        lock.lock()
                        finished = true
                        lock.unlock()

                        if thinkingActive {
                            continuation.yield(.thinkingFinished)
                        }
                        let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
                        continuation.yield(.completed(accumulatedText, thinking))
                        continuation.finish()
                        task?.cancel()
                        session?.invalidateAndCancel()
                        return
                    }
                }
                currentEventType = ""
                dataBuffer = ""
                continue
            }

            if trimmedLine.hasPrefix("event: ") {
                currentEventType = String(trimmedLine.dropFirst(7))
            } else if trimmedLine.hasPrefix("data: ") {
                let payload = String(trimmedLine.dropFirst(6))
                if dataBuffer.isEmpty {
                    dataBuffer = payload
                } else {
                    dataBuffer += "\n" + payload
                }
            }
            // Ignore comments (lines starting with :) and other fields
        }
    }

    // MARK: - Process Single SSE Event

    private enum EventResult {
        case continued
        case finished
    }

    private func processEvent(type: String, data: String) -> EventResult {
        guard let jsonData = data.data(using: .utf8) else { return .continued }

        switch type {

        case "response.output_text.delta":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? String {
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
                #if DEBUG
                if accumulatedText.count <= 50 {
                    print("[SSE] textDelta: \(delta.prefix(30))")
                }
                #endif
            }
            return .continued

        case "response.output_text.done":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let fullText = json["text"] as? String {
                if fullText.count > accumulatedText.count {
                    accumulatedText = fullText
                }
                emittedAnyOutput = true
            }
            return .continued

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

        case "response.reasoning_summary_text.done":
            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }
            return .continued

        case "response.completed":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let responseObj = json["response"] as? [String: Any] {
                if let text = Self.extractOutputText(from: responseObj) {
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

    // MARK: - Helpers

    private func yieldErrorAndFinish(_ error: OpenAIServiceError) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()

        guard !alreadyFinished else { return }
        continuation.yield(.error(error))
        continuation.finish()
    }

    private static func extractOutputText(from json: [String: Any]) -> String? {
        if let text = json["output_text"] as? String, !text.isEmpty {
            return text
        }

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
}
