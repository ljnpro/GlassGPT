import Foundation

extension OpenAISSEDelegate {
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
