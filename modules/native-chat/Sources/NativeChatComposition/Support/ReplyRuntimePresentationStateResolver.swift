import ChatPresentation
import ChatRuntimeModel

enum ReplyRuntimePresentationStateResolver {
    static func shouldShowRecoveryIndicator(
        for runtimeState: ReplyRuntimeState
    ) -> Bool {
        switch runtimeState.lifecycle {
        case .recoveringStatus, .recoveringPoll:
            true
        case .recoveringStream, .idle, .preparingInput, .uploadingAttachments,
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
                runtimeState.buffer.toolCalls.contains(where: { $0.status != .completed })
        )
    }
}
