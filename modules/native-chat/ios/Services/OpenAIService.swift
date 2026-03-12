import Foundation

// MARK: - Sendable DTO for crossing concurrency boundaries

struct APIMessage: Sendable {
    let role: MessageRole
    let content: String
    let imageData: Data?
    let fileAttachments: [FileAttachment]
    
    init(role: MessageRole, content: String, imageData: Data? = nil, fileAttachments: [FileAttachment] = []) {
        self.role = role
        self.content = content
        self.imageData = imageData
        self.fileAttachments = fileAttachments
    }
}

// MARK: - Stream Events

enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingStarted
    case thinkingFinished
    case responseCreated(String)      // response_id for recovery
    case completed(String, String?)   // (fullText, fullThinking?)
    case connectionLost               // Network disconnected mid-stream (eligible for auto-reconnect)
    case error(OpenAIServiceError)
    
    // Tool call events
    case webSearchStarted(String)     // tool call ID
    case webSearchSearching(String)   // tool call ID
    case webSearchCompleted(String)   // tool call ID
    case codeInterpreterStarted(String)    // tool call ID
    case codeInterpreterInterpreting(String) // tool call ID
    case codeInterpreterCodeDelta(String, String) // (tool call ID, code delta)
    case codeInterpreterCodeDone(String, String)  // (tool call ID, full code)
    case codeInterpreterCompleted(String)  // tool call ID
    
    // Annotation events
    case annotationAdded(URLCitation)
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
    private let filesURL = "https://api.openai.com/v1/files"
    private var currentDelegate: SSEDelegate?

    // MARK: - Upload File

    /// Upload a file to OpenAI for use in Responses API.
    /// Returns the file ID on success.
    nonisolated func uploadFile(data: Data, filename: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/files") else {
            throw OpenAIServiceError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()

        // Purpose field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("user_data\r\n".data(using: .utf8)!)

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)

        let mimeType = Self.mimeType(for: filename)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Upload failed"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let fileId = json["id"] as? String else {
            throw OpenAIServiceError.requestFailed("Failed to parse upload response")
        }

        #if DEBUG
        print("[OpenAI] File uploaded: \(filename) → \(fileId)")
        #endif

        return fileId
    }

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
                "stream": true,
                "tools": [
                    ["type": "web_search_preview"],
                    [
                        "type": "code_interpreter",
                        "container": ["type": "auto"]
                    ] as [String: Any]
                ]
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
            print("[OpenAI] Streaming request → \(model.rawValue), effort: \(reasoningEffort.rawValue), tools: [web_search, code_interpreter]")
            #endif

            // Use a dedicated URLSession with the delegate for real-time chunk delivery.
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
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
                let words = cleaned.split(separator: " ")
                if words.count > 5 {
                    return words.prefix(5).joined(separator: " ")
                }
                return cleaned
            }
        }

        return "New Chat"
    }

    // MARK: - Fetch Complete Response (Recovery)

    func fetchResponse(responseId: String, apiKey: String) async throws -> (text: String, thinking: String?, annotations: [URLCitation], toolCalls: [ToolCallInfo]) {
        guard let url = URL(string: "\(baseURL)/\(responseId)") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            throw OpenAIServiceError.httpError(httpResponse.statusCode, "Failed to fetch response")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIServiceError.requestFailed("Failed to parse response")
        }

        let status = json["status"] as? String ?? "unknown"
        if status == "in_progress" || status == "queued" {
            throw OpenAIServiceError.requestFailed("__IN_PROGRESS__")
        }

        if status == "failed" {
            throw OpenAIServiceError.requestFailed("Response generation failed on server")
        }

        let text = Self.extractOutputText(from: json) ?? ""

        var thinking: String? = nil
        var annotations: [URLCitation] = []
        var toolCalls: [ToolCallInfo] = []

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                let type = item["type"] as? String ?? ""

                // Extract reasoning summary
                if type == "reasoning" {
                    if let summary = item["summary"] as? [[String: Any]] {
                        let summaryTexts = summary.compactMap { $0["text"] as? String }
                        if !summaryTexts.isEmpty {
                            thinking = summaryTexts.joined()
                        }
                    }
                }

                // Extract web search calls
                if type == "web_search_call" {
                    let callId = item["id"] as? String ?? UUID().uuidString
                    var queries: [String]? = nil
                    if let action = item["action"] as? [String: Any],
                       let q = action["query"] as? String {
                        queries = [q]
                    }
                    toolCalls.append(ToolCallInfo(
                        id: callId,
                        type: .webSearch,
                        status: .completed,
                        queries: queries
                    ))
                }

                // Extract code interpreter calls
                if type == "code_interpreter_call" {
                    let callId = item["id"] as? String ?? UUID().uuidString
                    let code = item["code"] as? String
                    var results: [String]? = nil
                    if let resultArray = item["results"] as? [[String: Any]] {
                        results = resultArray.compactMap { result in
                            if let output = result["output"] as? String {
                                return output
                            }
                            return nil
                        }
                    }
                    toolCalls.append(ToolCallInfo(
                        id: callId,
                        type: .codeInterpreter,
                        status: .completed,
                        code: code,
                        results: results
                    ))
                }

                // Extract annotations from message content
                if type == "message" {
                    if let content = item["content"] as? [[String: Any]] {
                        for part in content {
                            if let partAnnotations = part["annotations"] as? [[String: Any]] {
                                for ann in partAnnotations {
                                    if let annType = ann["type"] as? String, annType == "url_citation",
                                       let url = ann["url"] as? String,
                                       let title = ann["title"] as? String {
                                        let startIdx = ann["start_index"] as? Int ?? 0
                                        let endIdx = ann["end_index"] as? Int ?? 0
                                        annotations.append(URLCitation(
                                            url: url,
                                            title: title,
                                            startIndex: startIdx,
                                            endIndex: endIdx
                                        ))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return (text: text, thinking: thinking, annotations: annotations, toolCalls: toolCalls)
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

            var contentArray: [[String: Any]] = []
            var hasMultiContent = false

            // Add text content
            if !message.content.isEmpty {
                contentArray.append([
                    "type": "input_text",
                    "text": message.content
                ])
            }

            // Add image if present
            if let imageData = message.imageData {
                hasMultiContent = true
                let base64 = imageData.base64EncodedString()
                contentArray.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(base64)"
                ])
            }

            // Add file attachments as input_file references
            for attachment in message.fileAttachments {
                if let fileId = attachment.fileId {
                    hasMultiContent = true
                    contentArray.append([
                        "type": "input_file",
                        "file_id": fileId
                    ])
                }
            }

            if hasMultiContent || contentArray.count > 1 {
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

    // MARK: - MIME Type Helper

    nonisolated static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "csv": return "text/csv"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - SSE Delegate

/// A URLSessionDataDelegate that receives data chunks in real-time and parses
/// SSE events, yielding StreamEvents through an AsyncStream continuation.
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

    // Accumulated tool call data
    private var accumulatedAnnotations: [URLCitation] = []

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

        lineBuffer += chunk
        processLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()

        guard !alreadyFinished else { return }

        if !lineBuffer.isEmpty {
            lineBuffer += "\n"
            processLines()
        }

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

            let nsError = error as NSError
            let isNetworkError = [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut,
                NSURLErrorDataNotAllowed,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorSecureConnectionFailed
            ].contains(nsError.code)

            if isNetworkError {
                if thinkingActive {
                    continuation.yield(.thinkingFinished)
                }
                continuation.yield(.connectionLost)
                continuation.finish()
            } else if emittedAnyOutput {
                if thinkingActive {
                    continuation.yield(.thinkingFinished)
                }
                let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
                continuation.yield(.completed(accumulatedText, thinking))
                continuation.finish()
            } else {
                continuation.yield(.error(.requestFailed(error.localizedDescription)))
                continuation.finish()
            }
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
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            let trimmedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line

            if trimmedLine.isEmpty {
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

        // MARK: Text Deltas
        case "response.output_text.delta":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? String {
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
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

        // MARK: Reasoning
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

        case "response.reasoning_text.delta":
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

        case "response.reasoning_text.done":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let fullText = json["text"] as? String {
                if fullText.count > accumulatedThinking.count {
                    accumulatedThinking = fullText
                }
            }
            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }
            return .continued

        // MARK: Web Search Events
        case "response.web_search_call.in_progress":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let itemId = json["item_id"] as? String {
                continuation.yield(.webSearchStarted(itemId))
                #if DEBUG
                print("[SSE] Web search started: \(itemId)")
                #endif
            }
            return .continued

        case "response.web_search_call.searching":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let itemId = json["item_id"] as? String {
                continuation.yield(.webSearchSearching(itemId))
            }
            return .continued

        case "response.web_search_call.completed":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let itemId = json["item_id"] as? String {
                continuation.yield(.webSearchCompleted(itemId))
                #if DEBUG
                print("[SSE] Web search completed: \(itemId)")
                #endif
            }
            return .continued

        // MARK: Code Interpreter Events
        case "response.code_interpreter_call.in_progress":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let itemId = json["item_id"] as? String {
                continuation.yield(.codeInterpreterStarted(itemId))
                #if DEBUG
                print("[SSE] Code interpreter started: \(itemId)")
                #endif
            }
            return .continued

        case "response.code_interpreter_call.interpreting":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let itemId = json["item_id"] as? String {
                continuation.yield(.codeInterpreterInterpreting(itemId))
            }
            return .continued

        case "response.code_interpreter_call_code.delta":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? String {
                let itemId = json["item_id"] as? String ?? ""
                continuation.yield(.codeInterpreterCodeDelta(itemId, delta))
            }
            return .continued

        case "response.code_interpreter_call_code.done":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let code = json["code"] as? String {
                let itemId = json["item_id"] as? String ?? ""
                continuation.yield(.codeInterpreterCodeDone(itemId, code))
            }
            return .continued

        case "response.code_interpreter_call.completed":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let itemId = json["item_id"] as? String {
                continuation.yield(.codeInterpreterCompleted(itemId))
                #if DEBUG
                print("[SSE] Code interpreter completed: \(itemId)")
                #endif
            }
            return .continued

        // MARK: Annotations
        case "response.output_text.annotation.added":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let annotation = json["annotation"] as? [String: Any],
               let annType = annotation["type"] as? String, annType == "url_citation",
               let url = annotation["url"] as? String,
               let title = annotation["title"] as? String {
                let startIdx = annotation["start_index"] as? Int ?? 0
                let endIdx = annotation["end_index"] as? Int ?? 0
                let citation = URLCitation(url: url, title: title, startIndex: startIdx, endIndex: endIdx)
                accumulatedAnnotations.append(citation)
                continuation.yield(.annotationAdded(citation))
                #if DEBUG
                print("[SSE] Citation: \(title) → \(url)")
                #endif
            }
            return .continued

        // MARK: Response Lifecycle
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

        case "response.created":
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let responseObj = json["response"] as? [String: Any],
               let responseId = responseObj["id"] as? String {
                continuation.yield(.responseCreated(responseId))
                #if DEBUG
                print("[SSE] Response created: \(responseId)")
                #endif
            }
            return .continued

        case "response.in_progress",
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
