import Foundation
import Synchronization

final class OpenAISSEDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<StreamEvent>.Continuation
    private let buffer = Mutex(SSEFrameBuffer())
    private let decoder = Mutex(SSEEventDecoder())
    private let finished = Mutex(false)
    private let session = Mutex(Optional<URLSession>.none)
    private let task = Mutex(Optional<URLSessionDataTask>.none)
    init(continuation: AsyncStream<StreamEvent>.Continuation) {
        self.continuation = continuation
        super.init()
    }
    func bind(session: URLSession) {
        self.session.withLock { $0 = session }
    }
    func bind(task: URLSessionDataTask) {
        self.task.withLock { $0 = task }
    }
    func cancel() {
        let shouldFinish = markFinishedIfNeeded()
        let task = takeTask()
        let session = takeSession()
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
        let emittedAnyOutput = decoder.withLock { $0.emittedAnyOutput }
        if !emittedAnyOutput && chunk.count < 200 {
            Loggers.openAI.debug("[SSE] Chunk (\(data.count) bytes): \(String(chunk.prefix(200)))")
        }
        #endif
        let frames = buffer.withLock { $0.append(chunk) }
        if process(frames: frames) {
            return
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isFinished else { return }
        let pendingFrames = buffer.withLock { $0.finishPendingFrames() }
        if process(frames: pendingFrames) {
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
            let emittedAnyOutput = decoder.withLock {
                $0.yieldThinkingFinishedIfNeeded(continuation: continuation)
                return $0.emittedAnyOutput
            }
            if isNetworkError || emittedAnyOutput {
                continuation.yield(.connectionLost)
            } else {
                continuation.yield(.error(.requestFailed(error.localizedDescription)))
            }

            continuation.finish()
            cleanupTransport()
            return
        }
        let sawTerminalEvent = decoder.withLock { $0.sawTerminalEvent }
        if !sawTerminalEvent {
            decoder.withLock {
                $0.yieldThinkingFinishedIfNeeded(continuation: continuation)
            }
            continuation.yield(.connectionLost)
        }

        continuation.finish()
        cleanupTransport()
    }

    private var isFinished: Bool {
        finished.withLock { $0 }
    }

    private func process(frames: [SSEFrame]) -> Bool {
        for frame in frames {
            let result = decoder.withLock { state in
                state.decode(frame: frame, continuation: continuation)
            }
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
            let snapshot = decoder.withLock { state in
                state.yieldThinkingFinishedIfNeeded(continuation: continuation)
                return (
                    state.accumulatedText,
                    state.terminalThinking,
                    state.terminalFilePathAnnotations
                )
            }
            continuation.yield(
                .completed(
                    snapshot.0,
                    snapshot.1,
                    snapshot.2
                )
            )
            continuation.finish()
            cleanupTransport()
            return true
        case .terminalIncomplete(let message):
            guard markFinishedIfNeeded() else { return true }
            let snapshot = decoder.withLock { state in
                state.yieldThinkingFinishedIfNeeded(continuation: continuation)
                return (
                    state.accumulatedText,
                    state.terminalThinking,
                    state.terminalFilePathAnnotations
                )
            }
            continuation.yield(
                .incomplete(
                    snapshot.0,
                    snapshot.1,
                    snapshot.2,
                    message
                )
            )
            continuation.finish()
            cleanupTransport()
            return true
        case .terminalError:
            guard markFinishedIfNeeded() else { return true }
            decoder.withLock {
                $0.yieldThinkingFinishedIfNeeded(continuation: continuation)
            }
            continuation.finish()
            cleanupTransport()
            return true
        }
    }

    private func yieldErrorAndFinish(_ error: OpenAIServiceError) {
        guard markFinishedIfNeeded() else { return }
        continuation.yield(.error(error))
        continuation.finish()
        cleanupTransport()
    }

    private func markFinishedIfNeeded() -> Bool {
        finished.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
    }

    private func cleanupTransport() {
        let task = takeTask()
        let session = takeSession()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    private func takeTask() -> URLSessionDataTask? {
        task.withLock { state in
            defer { state = nil }
            return state
        }
    }

    private func takeSession() -> URLSession? {
        session.withLock { state in
            defer { state = nil }
            return state
        }
    }
}
