import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
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
    var thinkingPresentationState: ThinkingPresentationState?

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
            isThinking: false,
            thinkingPresentationState: nil
        )
    }
}

enum SessionVisibilityCoordinator {
    @MainActor
    static func visibleState(
        from session: ReplySession,
        runtimeState: ReplyRuntimeState,
        draftMessage: Message?
    ) -> ChatVisibleSessionState {
        if let draftMessage,
           shouldUseRecoverableDraftPlaceholder(
               for: draftMessage,
               runtimeState: runtimeState
           ) {
            return recoverableRuntimePlaceholderState(
                for: draftMessage,
                session: session,
                runtimeState: runtimeState
            )
        }

        return ChatVisibleSessionState(
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
            isRecovering: ReplyRuntimePresentationStateResolver.shouldShowRecoveryIndicator(for: runtimeState),
            isThinking: runtimeState.isThinking,
            thinkingPresentationState: ReplyRuntimePresentationStateResolver.thinkingPresentationState(for: runtimeState)
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

    static func recoverableDraftPlaceholderState(
        for message: Message,
        requestConfiguration: (ModelType, ReasoningEffort, ServiceTier)?
    ) -> ChatVisibleSessionState {
        ChatVisibleSessionState(
            draftMessage: message,
            currentStreamingText: message.content,
            currentThinkingText: "",
            activeToolCalls: placeholderToolCalls(from: message.toolCalls),
            liveCitations: message.annotations,
            liveFilePathAnnotations: message.filePathAnnotations,
            lastSequenceNumber: message.lastSequenceNumber,
            activeRequestModel: requestConfiguration?.0,
            activeRequestEffort: requestConfiguration?.1,
            activeRequestUsesBackgroundMode: message.usedBackgroundMode,
            activeRequestServiceTier: requestConfiguration?.2 ?? .standard,
            isStreaming: false,
            isRecovering: true,
            isThinking: false,
            thinkingPresentationState: nil
        )
    }

    @MainActor
    static func apply(
        _ visibleState: ChatVisibleSessionState,
        to state: any ChatSessionCoordinatorStateAccess
    ) {
        state.draftMessage = visibleState.draftMessage
        state.currentStreamingText = visibleState.currentStreamingText
        state.currentThinkingText = visibleState.currentThinkingText
        state.activeToolCalls = visibleState.activeToolCalls
        state.liveCitations = visibleState.liveCitations
        state.liveFilePathAnnotations = visibleState.liveFilePathAnnotations
        state.lastSequenceNumber = visibleState.lastSequenceNumber
        state.activeRequestModel = visibleState.activeRequestModel
        state.activeRequestEffort = visibleState.activeRequestEffort
        state.activeRequestUsesBackgroundMode = visibleState.activeRequestUsesBackgroundMode
        state.activeRequestServiceTier = visibleState.activeRequestServiceTier
        state.isStreaming = visibleState.isStreaming
        state.isThinking = visibleState.isThinking
        state.isRecovering = visibleState.isRecovering
        state.thinkingPresentationState = visibleState.thinkingPresentationState
    }

    private static func shouldUseRecoverableDraftPlaceholder(
        for draftMessage: Message,
        runtimeState: ReplyRuntimeState
    ) -> Bool {
        guard !draftMessage.isComplete,
              draftMessage.responseId != nil,
              !runtimeState.isStreaming
        else {
            return false
        }

        let draftHasVisibleState = !draftMessage.content.isEmpty ||
            !((draftMessage.thinking ?? "").isEmpty) ||
            !draftMessage.toolCalls.isEmpty ||
            !draftMessage.annotations.isEmpty ||
            !draftMessage.filePathAnnotations.isEmpty ||
            draftMessage.lastSequenceNumber != nil

        guard draftHasVisibleState else {
            return false
        }

        guard runtimeState.isRecovering else {
            return true
        }

        return !runtimeHasVisibleState(runtimeState)
    }

    private static func runtimeHasVisibleState(_ runtimeState: ReplyRuntimeState) -> Bool {
        !runtimeState.buffer.text.isEmpty ||
            !runtimeState.buffer.thinking.isEmpty ||
            !runtimeState.buffer.toolCalls.isEmpty ||
            !runtimeState.buffer.citations.isEmpty ||
            !runtimeState.buffer.filePathAnnotations.isEmpty
    }

    private static func recoverableRuntimePlaceholderState(
        for draftMessage: Message,
        session: ReplySession,
        runtimeState: ReplyRuntimeState
    ) -> ChatVisibleSessionState {
        ChatVisibleSessionState(
            draftMessage: draftMessage,
            currentStreamingText: draftMessage.content,
            currentThinkingText: "",
            activeToolCalls: placeholderToolCalls(from: draftMessage.toolCalls),
            liveCitations: draftMessage.annotations,
            liveFilePathAnnotations: draftMessage.filePathAnnotations,
            lastSequenceNumber: draftMessage.lastSequenceNumber,
            activeRequestModel: session.request.model,
            activeRequestEffort: session.request.effort,
            activeRequestUsesBackgroundMode: draftMessage.usedBackgroundMode,
            activeRequestServiceTier: session.request.serviceTier,
            isStreaming: runtimeState.isStreaming,
            isRecovering: true,
            isThinking: runtimeState.isThinking,
            thinkingPresentationState: nil
        )
    }
}
