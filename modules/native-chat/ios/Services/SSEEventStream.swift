import Foundation

@MainActor
final class SSEEventStream {
    private var currentDelegate: OpenAISSEDelegate?

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let delegate = OpenAISSEDelegate(continuation: continuation)
            self.currentDelegate = delegate

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

    func cancel() {
        currentDelegate?.cancel()
        currentDelegate = nil
    }
}

private final class OpenAISSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            yieldErrorAndFinish(.requestFailed("Invalid response"))
            return
        }

        #if DEBUG
        Loggers.openAI.debug("[SSE] HTTP status: \(httpResponse.statusCode)")
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
            Loggers.openAI.debug("[SSE] Chunk (\(data.count) bytes): \(String(chunk.prefix(200)))")
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

        if let error {
            #if DEBUG
            Loggers.openAI.debug("[SSE] Connection error: \(error.localizedDescription)")
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

    private enum EventResult {
        case continued
        case terminalCompleted
        case terminalIncomplete(String?)
        case terminalError
    }

    private func processEvent(type: String, data: String) -> EventResult {
        guard let jsonData = data.data(using: .utf8) else {
            return .continued
        }

        let json: [String: Any]
        do {
            json = try JSONCoding.jsonObject(from: jsonData)
        } catch {
            return .continued
        }

        let sequenceNumber = OpenAIStreamEventTranslator.extractSequenceNumber(from: json)

        if let translated = OpenAIStreamEventTranslator.translate(eventType: type, data: json) {
            switch translated {
            case .textDelta(let delta):
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
                yieldSequenceIfNeeded(sequenceNumber)
                return .continued

            case .thinkingDelta(let delta):
                if !thinkingActive {
                    thinkingActive = true
                    continuation.yield(.thinkingStarted)
                }
                emittedAnyOutput = true
                accumulatedThinking += delta
                continuation.yield(.thinkingDelta(delta))
                yieldSequenceIfNeeded(sequenceNumber)
                return .continued

            case .thinkingFinished:
                if thinkingActive {
                    thinkingActive = false
                    continuation.yield(.thinkingFinished)
                }
                yieldSequenceIfNeeded(sequenceNumber)
                return .continued

            case .responseCreated(let responseId):
                continuation.yield(.responseCreated(responseId))
                yieldSequenceIfNeeded(sequenceNumber)
                #if DEBUG
                Loggers.openAI.debug("[SSE] Response created: \(responseId)")
                #endif
                return .continued

            case .sequenceUpdate(_):
                yieldSequenceIfNeeded(sequenceNumber)
                return .continued

            case .filePathAnnotationAdded(let annotation):
                accumulatedFilePathAnnotations.append(annotation)
                continuation.yield(.filePathAnnotationAdded(annotation))
                yieldSequenceIfNeeded(sequenceNumber)
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

            case .incomplete(let fullText, let fullThinking, let filePathAnns, let message):
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
                return .terminalIncomplete(message)

            case .error(let error):
                sawTerminalEvent = true
                continuation.yield(.error(error))
                return .terminalError

            default:
                continuation.yield(translated)
                yieldSequenceIfNeeded(sequenceNumber)
                return .continued
            }
        }

        switch type {
        case "response.output_text.done":
            if let fullText = json["text"] as? String, !fullText.isEmpty {
                accumulatedText = fullText
                emittedAnyOutput = true
            }
            yieldSequenceIfNeeded(sequenceNumber)
            return .continued

        case "response.queued",
             "response.in_progress",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            yieldSequenceIfNeeded(sequenceNumber)
            return .continued

        default:
            #if DEBUG
            Loggers.openAI.debug("[SSE] Unhandled event: \(type)")
            #endif
            return .continued
        }
    }

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

        case .terminalIncomplete(let message):
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
            continuation.yield(.incomplete(accumulatedText, thinking, filePathAnns, message))
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

    private func yieldSequenceIfNeeded(_ sequenceNumber: Int?) {
        guard let sequenceNumber else { return }
        continuation.yield(.sequenceUpdate(sequenceNumber))
    }
}
