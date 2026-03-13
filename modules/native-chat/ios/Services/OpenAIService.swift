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
    case responseCreated(String)
    case completed(String, String?, [FilePathAnnotation]?)
    case connectionLost
    case error(OpenAIServiceError)

    // Tool call events
    case webSearchStarted(String)
    case webSearchSearching(String)
    case webSearchCompleted(String)
    case codeInterpreterStarted(String)
    case codeInterpreterInterpreting(String)
    case codeInterpreterCodeDelta(String, String)
    case codeInterpreterCodeDone(String, String)
    case codeInterpreterCompleted(String)
    case fileSearchStarted(String)
    case fileSearchSearching(String)
    case fileSearchCompleted(String)

    // Annotation events
    case annotationAdded(URLCitation)
    case filePathAnnotationAdded(FilePathAnnotation)
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

// MARK: - Polling Fetch Result

struct OpenAIResponseFetchResult {
    enum Status: String, Sendable {
        case queued
        case inProgress = "in_progress"
        case completed
        case failed
        case incomplete
        case unknown
    }

    let status: Status
    let text: String
    let thinking: String?
    let annotations: [URLCitation]
    let toolCalls: [ToolCallInfo]
    let filePathAnnotations: [FilePathAnnotation]
    let errorMessage: String?
}

// MARK: - OpenAI Service

@MainActor
final class OpenAIService {

    private var currentDelegate: SSEDelegate?
    private var responsesURL: String {
        "\(FeatureFlags.openAIBaseURL)/responses"
    }

    // MARK: - Upload File

    nonisolated func uploadFile(data: Data, filename: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "\(FeatureFlags.openAIBaseURL)/files") else {
            throw OpenAIServiceError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        FeatureFlags.applyCloudflareAuthorization(to: &request)

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("user_data\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)

        let mimeType = Self.mimeType(for: filename)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

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

        guard
            let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let fileId = json["id"] as? String
        else {
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
        reasoningEffort: ReasoningEffort,
        vectorStoreIds: [String] = []
    ) -> AsyncStream<StreamEvent> {
        cancelStream()

        let responsesURL = self.responsesURL

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let delegate = SSEDelegate(continuation: continuation)
            self.currentDelegate = delegate

            guard let url = URL(string: responsesURL) else {
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
            FeatureFlags.applyCloudflareAuthorization(to: &request)

            let input = Self.buildInputArray(messages: messages)

            var tools: [[String: Any]] = [
                ["type": "web_search_preview"],
                [
                    "type": "code_interpreter",
                    "container": ["type": "auto"]
                ]
            ]

            if !vectorStoreIds.isEmpty {
                tools.append([
                    "type": "file_search",
                    "vector_store_ids": vectorStoreIds
                ])
            }

            var body: [String: Any] = [
                "model": model.rawValue,
                "input": input,
                "stream": true,
                "store": true,
                "tools": tools
            ]

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
            let toolNames = vectorStoreIds.isEmpty ? "[web_search, code_interpreter]" : "[web_search, code_interpreter, file_search]"
            print("[OpenAI] Streaming request → \(model.rawValue), effort: \(reasoningEffort.rawValue), tools: \(toolNames)")
            #endif

            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            config.waitsForConnectivity = false
            config.timeoutIntervalForResource = 600

            let delegateQueue = OperationQueue()
            delegateQueue.name = "com.glassgpt.sse"
            delegateQueue.maxConcurrentOperationCount = 1
            delegateQueue.qualityOfService = .userInitiated

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: delegateQueue)
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
        guard let url = URL(string: responsesURL) else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        FeatureFlags.applyCloudflareAuthorization(to: &request)

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

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = Self.extractOutputText(from: json) {
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let words = cleaned.split(separator: " ")
            if words.count > 5 {
                return words.prefix(5).joined(separator: " ")
            }
            return cleaned
        }

        return "New Chat"
    }

    // MARK: - Fetch Complete Response (Polling Recovery)

    func fetchResponse(responseId: String, apiKey: String) async throws -> OpenAIResponseFetchResult {
        guard let url = URL(string: "\(responsesURL)/\(responseId)") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        FeatureFlags.applyCloudflareAuthorization(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Failed to fetch response"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIServiceError.requestFailed("Failed to parse response")
        }

        let statusString = json["status"] as? String ?? "unknown"
        let status = OpenAIResponseFetchResult.Status(rawValue: statusString) ?? .unknown
        let text = Self.extractOutputText(from: json) ?? ""
        let thinking = Self.extractReasoningText(from: json)

        var annotations: [URLCitation] = []
        var toolCalls: [ToolCallInfo] = []
        let filePathAnns = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: json)

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                let type = item["type"] as? String ?? ""

                if type == "web_search_call" {
                    let callId = item["id"] as? String ?? UUID().uuidString
                    var queries: [String]? = nil

                    if let action = item["action"] as? [String: Any],
                       let q = action["query"] as? String {
                        queries = [q]
                    } else if let q = item["query"] as? String {
                        queries = [q]
                    }

                    toolCalls.append(ToolCallInfo(
                        id: callId,
                        type: .webSearch,
                        status: .completed,
                        queries: queries
                    ))
                }

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

                if type == "file_search_call" {
                    let callId = item["id"] as? String ?? UUID().uuidString
                    var queries: [String]? = nil

                    if let q = item["query"] as? String {
                        queries = [q]
                    } else if let q = item["queries"] as? [String] {
                        queries = q
                    }

                    toolCalls.append(ToolCallInfo(
                        id: callId,
                        type: .fileSearch,
                        status: .completed,
                        queries: queries
                    ))
                }

                if type == "message",
                   let content = item["content"] as? [[String: Any]] {
                    for part in content {
                        if let partAnnotations = part["annotations"] as? [[String: Any]] {
                            for ann in partAnnotations {
                                if let annType = ann["type"] as? String,
                                   annType == "url_citation",
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

        let errorMessage = Self.extractErrorMessage(from: json)

        return OpenAIResponseFetchResult(
            status: status,
            text: text,
            thinking: thinking,
            annotations: annotations,
            toolCalls: toolCalls,
            filePathAnnotations: filePathAnns,
            errorMessage: errorMessage
        )
    }

    // MARK: - Validate API Key

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: "\(FeatureFlags.openAIBaseURL)/models") else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        FeatureFlags.applyCloudflareAuthorization(to: &request)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Extractors

    private nonisolated static func extractOutputText(from json: [String: Any]) -> String? {
        OpenAIStreamEventTranslator.extractOutputText(from: json)
    }

    private nonisolated static func extractReasoningText(from json: [String: Any]) -> String? {
        OpenAIStreamEventTranslator.extractReasoningText(from: json)
    }

    private nonisolated static func extractErrorMessage(from json: [String: Any]) -> String? {
        OpenAIStreamEventTranslator.extractErrorMessage(from: json)
    }

    // MARK: - Build Input Array

    nonisolated static func buildInputArray(messages: [APIMessage]) -> [[String: Any]] {
        var input: [[String: Any]] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"

            var contentArray: [[String: Any]] = []
            var hasMultiContent = false

            if !message.content.isEmpty {
                contentArray.append([
                    "type": "input_text",
                    "text": message.content
                ])
            }

            if let imageData = message.imageData {
                hasMultiContent = true
                let base64 = imageData.base64EncodedString()
                contentArray.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(base64)"
                ])
            }

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

private final class SSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let continuation: AsyncStream<StreamEvent>.Continuation
    private let lock = NSLock()

    private var lineBuffer = ""
    private var currentEventType = ""
    private var dataBuffer = ""

    private var accumulatedText = ""
    private var accumulatedThinking = ""
    private var accumulatedFilePathAnnotations: [FilePathAnnotation] = []
    private var thinkingActive = false
    private var emittedAnyOutput = false
    private var finished = false
    private var sawTerminalEvent = false

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
        lock.unlock()

        guard !alreadyFinished else { return }

        if !lineBuffer.isEmpty {
            lineBuffer += "\n"
            processLines()
        }

        if !currentEventType.isEmpty && !dataBuffer.isEmpty {
            let result = processEvent(type: currentEventType, data: dataBuffer)
            currentEventType = ""
            dataBuffer = ""
            if handleTerminalResult(result) { return }
        }

        lock.lock()
        let becameFinished = !finished
        if becameFinished {
            finished = true
        }
        lock.unlock()

        guard becameFinished else { return }

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

            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }

            if isNetworkError || emittedAnyOutput {
                continuation.yield(.connectionLost)
            } else {
                continuation.yield(.error(.requestFailed(error.localizedDescription)))
            }

            continuation.finish()
            session.invalidateAndCancel()
            return
        }

        if !sawTerminalEvent {
            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }
            continuation.yield(.connectionLost)
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
                    if handleTerminalResult(result) { return }
                } else {
                    currentEventType = ""
                    dataBuffer = ""
                }
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
        case terminalCompleted
        case terminalError
    }

    private func processEvent(type: String, data: String) -> EventResult {
        guard
            let jsonData = data.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return .continued
        }

        if let translated = OpenAIStreamEventTranslator.translate(eventType: type, data: json) {
            switch translated {
            case .textDelta(let delta):
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
                return .continued

            case .thinkingDelta(let delta):
                if !thinkingActive {
                    thinkingActive = true
                    continuation.yield(.thinkingStarted)
                }
                emittedAnyOutput = true
                accumulatedThinking += delta
                continuation.yield(.thinkingDelta(delta))
                return .continued

            case .thinkingFinished:
                if thinkingActive {
                    thinkingActive = false
                    continuation.yield(.thinkingFinished)
                }
                return .continued

            case .responseCreated(let responseId):
                continuation.yield(.responseCreated(responseId))
                #if DEBUG
                print("[SSE] Response created: \(responseId)")
                #endif
                return .continued

            case .filePathAnnotationAdded(let annotation):
                accumulatedFilePathAnnotations.append(annotation)
                continuation.yield(.filePathAnnotationAdded(annotation))
                return .continued

            case .completed(let fullText, let fullThinking, let filePathAnns):
                sawTerminalEvent = true
                if !fullText.isEmpty {
                    accumulatedText = fullText
                }
                if let fullThinking, !fullThinking.isEmpty {
                    accumulatedThinking = fullThinking
                }
                if let filePathAnns, !filePathAnns.isEmpty {
                    accumulatedFilePathAnnotations = filePathAnns
                }
                emittedAnyOutput = emittedAnyOutput || !accumulatedText.isEmpty || !accumulatedThinking.isEmpty
                return .terminalCompleted

            case .error(let error):
                sawTerminalEvent = true
                continuation.yield(.error(error))
                return .terminalError

            default:
                continuation.yield(translated)
                return .continued
            }
        }

        switch type {
        case "response.output_text.done":
            if let fullText = json["text"] as? String, !fullText.isEmpty {
                accumulatedText = fullText
                emittedAnyOutput = true
            }
            return .continued

        case "response.queued",
             "response.in_progress",
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

    private func handleTerminalResult(_ result: EventResult) -> Bool {
        switch result {
        case .continued:
            return false

        case .terminalCompleted:
            lock.lock()
            let alreadyFinished = finished
            finished = true
            lock.unlock()

            guard !alreadyFinished else { return true }

            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }

            let thinking: String? = accumulatedThinking.isEmpty ? nil : accumulatedThinking
            let filePathAnns: [FilePathAnnotation]? = accumulatedFilePathAnnotations.isEmpty ? nil : accumulatedFilePathAnnotations
            continuation.yield(.completed(accumulatedText, thinking, filePathAnns))
            continuation.finish()
            task?.cancel()
            session?.invalidateAndCancel()
            return true

        case .terminalError:
            lock.lock()
            let alreadyFinished = finished
            finished = true
            lock.unlock()

            guard !alreadyFinished else { return true }

            if thinkingActive {
                thinkingActive = false
                continuation.yield(.thinkingFinished)
            }

            continuation.finish()
            task?.cancel()
            session?.invalidateAndCancel()
            return true
        }
    }

    private func yieldErrorAndFinish(_ error: OpenAIServiceError) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()

        guard !alreadyFinished else { return }
        continuation.yield(.error(error))
        continuation.finish()
    }
}
