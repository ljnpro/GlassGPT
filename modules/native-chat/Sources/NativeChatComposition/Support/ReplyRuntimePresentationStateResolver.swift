import ChatPresentation
import ChatRuntimeModel

enum ReplyRuntimePresentationStateResolver {
    static func shouldShowRecoveryIndicator(
        for runtimeState: ReplyRuntimeState
    ) -> Bool {
        if runtimeState.pendingRecoveryRestart {
            return true
        }

        return switch runtimeState.lifecycle {
        case .recoveringStatus, .recoveringStream, .recoveringPoll:
            true
        case .idle, .preparingInput, .uploadingAttachments,
             .streaming, .detached, .finalizing, .completed, .failed:
            false
        }
    }

    static func thinkingPresentationState(
        for runtimeState: ReplyRuntimeState
    ) -> ThinkingPresentationState? {
        guard !runtimeState.buffer.thinking.isEmpty else {
            return nil
        }

        return ThinkingPresentationState.resolve(
            hasResponseText: !runtimeState.buffer.text.isEmpty,
            isThinking: runtimeState.isThinking,
            isAwaitingResponse: runtimeState.isStreaming ||
                runtimeState.isRecovering ||
                runtimeState.pendingRecoveryRestart ||
                runtimeState.buffer.toolCalls.contains(where: { $0.status != .completed })
        )
    }
}
