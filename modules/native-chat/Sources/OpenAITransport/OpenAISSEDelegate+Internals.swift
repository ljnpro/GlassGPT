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

    func process(frames: [SSEFrame]) -> Bool {
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

    func handleTerminalResult(_ result: SSEEventTerminalResult) -> Bool {
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
}
