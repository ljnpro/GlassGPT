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
    var visibleRecoveryPhase: RecoveryPhase
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
            visibleRecoveryPhase: .idle,
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
        from session: ResponseSession,
        draftMessage: Message?
    ) -> ChatVisibleSessionState {
        ChatVisibleSessionState(
            draftMessage: draftMessage,
            currentStreamingText: session.currentText,
            currentThinkingText: session.currentThinking,
            activeToolCalls: session.toolCalls,
            liveCitations: session.citations,
            liveFilePathAnnotations: session.filePathAnnotations,
            lastSequenceNumber: session.lastSequenceNumber,
            activeRequestModel: session.requestModel,
            activeRequestEffort: session.requestEffort,
            activeRequestUsesBackgroundMode: session.requestUsesBackgroundMode,
            activeRequestServiceTier: session.requestServiceTier,
            isStreaming: session.runtimeState.isStreaming,
            isRecovering: session.runtimeState.isRecovering,
            visibleRecoveryPhase: session.runtimeState.recoveryPhase,
            isThinking: session.runtimeState.isThinking
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
