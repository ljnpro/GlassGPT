import Foundation

struct ChatVisibleSessionState {
    let draftMessage: Message?
    let currentStreamingText: String
    let currentThinkingText: String
    let activeToolCalls: [ToolCallInfo]
    let liveCitations: [URLCitation]
    let liveFilePathAnnotations: [FilePathAnnotation]
    let lastSequenceNumber: Int?
    let activeRequestModel: ModelType?
    let activeRequestEffort: ReasoningEffort?
    let activeRequestUsesBackgroundMode: Bool
    let activeRequestServiceTier: ServiceTier
    let isStreaming: Bool
    let isRecovering: Bool
    let visibleRecoveryPhase: RecoveryPhase
    let isThinking: Bool
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
        ChatVisibleSessionState(
            draftMessage: clearDraft ? nil : draftMessage,
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
