import Foundation

final class OpenAISSEDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<StreamEvent>.Continuation
    private let lock = NSLock()

    private var buffer = SSEFrameBuffer()
    private var decoder = SSEEventDecoder()
    private var finished = false

    weak var session: URLSession?
    weak var task: URLSessionDataTask?

    init(continuation: AsyncStream<StreamEvent>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func cancel() {
        let shouldFinish = markFinishedIfNeeded()

        task?.cancel()
        session?.invalidateAndCancel()

        if shouldFinish {
            continuation.finish()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
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
        guard !isFinished else { return }

        #if DEBUG
        if !decoder.emittedAnyOutput && chunk.count < 200 {
            Loggers.openAI.debug("[SSE] Chunk (\(data.count) bytes): \(String(chunk.prefix(200)))")
        }
        #endif

        if process(frames: buffer.append(chunk)) {
            return
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isFinished else { return }

        if process(frames: buffer.finishPendingFrames()) {
            return
        }

        guard markFinishedIfNeeded() else { return }

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

            decoder.yieldThinkingFinishedIfNeeded(continuation: continuation)

            if isNetworkError || decoder.emittedAnyOutput {
                continuation.yield(.connectionLost)
            } else {
                continuation.yield(.error(.requestFailed(error.localizedDescription)))
            }

            continuation.finish()
            session.invalidateAndCancel()
            return
        }

        if !decoder.sawTerminalEvent {
            decoder.yieldThinkingFinishedIfNeeded(continuation: continuation)
            continuation.yield(.connectionLost)
        }

        continuation.finish()
        session.invalidateAndCancel()
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func process(frames: [SSEFrame]) -> Bool {
        for frame in frames {
            let result = decoder.decode(frame: frame, continuation: continuation)
            if handleTerminalResult(result) {
                return true
            }
        }

        return false
    }

    private func handleTerminalResult(_ result: SSEEventTerminalResult) -> Bool {
        switch result {
        case .continued:
            return false

        case .terminalCompleted:
            guard markFinishedIfNeeded() else { return true }
            decoder.yieldThinkingFinishedIfNeeded(continuation: continuation)
            continuation.yield(
                .completed(
                    decoder.accumulatedText,
                    decoder.terminalThinking,
                    decoder.terminalFilePathAnnotations
                )
            )
            continuation.finish()
            task?.cancel()
            session?.invalidateAndCancel()
            return true

        case .terminalIncomplete(let message):
            guard markFinishedIfNeeded() else { return true }
            decoder.yieldThinkingFinishedIfNeeded(continuation: continuation)
            continuation.yield(
                .incomplete(
                    decoder.accumulatedText,
                    decoder.terminalThinking,
                    decoder.terminalFilePathAnnotations,
                    message
                )
            )
            continuation.finish()
            task?.cancel()
            session?.invalidateAndCancel()
            return true

        case .terminalError:
            guard markFinishedIfNeeded() else { return true }
            decoder.yieldThinkingFinishedIfNeeded(continuation: continuation)
            continuation.finish()
            task?.cancel()
            session?.invalidateAndCancel()
            return true
        }
    }

    private func yieldErrorAndFinish(_ error: OpenAIServiceError) {
        guard markFinishedIfNeeded() else { return }
        continuation.yield(.error(error))
        continuation.finish()
    }

    private func markFinishedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else { return false }
        finished = true
        return true
    }
}
