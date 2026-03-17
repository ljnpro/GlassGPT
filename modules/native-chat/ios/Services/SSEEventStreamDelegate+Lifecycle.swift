import Foundation

extension OpenAISSEDelegate {
    var isFinished: Bool {
        finished.withLock { $0 }
    }

    func yieldErrorAndFinish(_ error: OpenAIServiceError) {
        guard markFinishedIfNeeded() else { return }
        continuation.yield(.error(error))
        continuation.finish()
        cleanupTransport()
    }

    func markFinishedIfNeeded() -> Bool {
        finished.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
    }

    func cleanupTransport() {
        let task = takeTask()
        let session = takeSession()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func takeTask() -> URLSessionDataTask? {
        task.withLock { state in
            defer { state = nil }
            return state
        }
    }

    func takeSession() -> URLSession? {
        session.withLock { state in
            defer { state = nil }
            return state
        }
    }
}
