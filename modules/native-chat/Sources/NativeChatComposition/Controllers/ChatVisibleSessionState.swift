import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

struct ChatVisibleSessionState {
    var draftMessage: Message?
    var currentStreamingText: String
    var currentThinkingText: String
    var activeToolCalls: [ToolCallInfo]
    var liveCitations: [URLCitation]
    var liveFilePathAnnotations: [FilePathAnnotation]
    var lastSequenceNumber: Int?
    var activeRequestModel: ModelType?
    var activeRequestEffort: ReasoningEffort?
    var activeRequestUsesBackgroundMode: Bool
    var activeRequestServiceTier: ServiceTier
    var isStreaming: Bool
    var isRecovering: Bool
    var isThinking: Bool

    static func empty() -> ChatVisibleSessionState {
        ChatVisibleSessionState(
            draftMessage: nil,
            currentStreamingText: "",
            currentThinkingText: "",
            activeToolCalls: [],
            liveCitations: [],
            liveFilePathAnnotations: [],
            lastSequenceNumber: nil,
            activeRequestModel: nil,
            activeRequestEffort: nil,
            activeRequestUsesBackgroundMode: false,
            activeRequestServiceTier: .standard,
            isStreaming: false,
            isRecovering: false,
            isThinking: false
        )
    }
}

enum SessionVisibilityCoordinator {
    static func liveDraftMessageID(
        visibleMessageID: UUID?,
        messages: [Message]
    ) -> UUID? {
        guard let visibleMessageID,
              messages.contains(where: { $0.id == visibleMessageID })
        else {
            return nil
        }

        return visibleMessageID
    }

    static func shouldShowDetachedStreamingBubble(
        isStreaming: Bool,
        liveDraftMessageID: UUID?
    ) -> Bool {
        isStreaming && liveDraftMessageID == nil
    }

    @MainActor
    static func visibleState(
        from session: ReplySession,
        runtimeState: ReplyRuntimeState,
        draftMessage: Message?
    ) -> ChatVisibleSessionState {
        ChatVisibleSessionState(
            draftMessage: draftMessage,
            currentStreamingText: runtimeState.buffer.text,
            currentThinkingText: runtimeState.buffer.thinking,
            activeToolCalls: runtimeState.buffer.toolCalls,
            liveCitations: runtimeState.buffer.citations,
            liveFilePathAnnotations: runtimeState.buffer.filePathAnnotations,
            lastSequenceNumber: runtimeState.lastSequenceNumber,
            activeRequestModel: session.request.model,
            activeRequestEffort: session.request.effort,
            activeRequestUsesBackgroundMode: session.request.usesBackgroundMode,
            activeRequestServiceTier: session.request.serviceTier,
            isStreaming: runtimeState.isStreaming,
            isRecovering: runtimeState.isRecovering,
            isThinking: runtimeState.isThinking
        )
    }

    static func clearedState(
        retaining draftMessage: Message?,
        clearDraft: Bool
    ) -> ChatVisibleSessionState {
        var state = ChatVisibleSessionState.empty()
        state.draftMessage = clearDraft ? nil : draftMessage
        return state
    }
}
