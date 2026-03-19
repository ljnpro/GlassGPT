import Foundation
import Synchronization

final class OpenAISSEDelegate: NSObject, URLSessionDataDelegate {
    let continuation: AsyncStream<StreamEvent>.Continuation
    let buffer = Mutex(SSEFrameBuffer())
    let decoder = Mutex(SSEEventDecoder())
    let finished = Mutex(false)
    let session = Mutex(URLSession?.none)
    let task = Mutex(URLSessionDataTask?.none)

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
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            yieldErrorAndFinish(.requestFailed("Invalid response"))
            return
        }
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

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        guard !isFinished else { return }
        let frames = buffer.withLock { $0.append(chunk) }
        if process(frames: frames) {
            return
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
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
}
