import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func makeRecoverySession(for message: Message) -> ReplySession? {
        guard let conversation = message.conversation else { return nil }
        let configuration = controller.conversationCoordinator.sessionRequestConfiguration(for: conversation)

        return ReplySession(
            assistantReplyID: AssistantReplyID(rawValue: message.id),
            message: message,
            conversationID: conversation.id,
            request: ResponseRequestContext(
                apiKey: controller.apiKey,
                messages: nil,
                model: configuration.0,
                effort: configuration.1,
                usesBackgroundMode: message.usedBackgroundMode,
                serviceTier: configuration.2
            )
        )
    }

    func registerSession(_ session: ReplySession, execution: SessionExecutionState, visible: Bool) {
        controller.sessionRegistry.register(session, execution: execution, visible: visible) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }
        ensureRuntimeSessionRegistered(for: session)

        if visible {
            bindVisibleSession(messageID: session.messageID)
        } else if visibleSessionMessageID == session.messageID {
            syncVisibleState(from: session)
        }
    }

    func isSessionActive(_ session: ReplySession) -> Bool {
        controller.sessionRegistry.contains(session)
    }

    func bindVisibleSession(messageID: UUID?) {
        controller.sessionRegistry.bindVisibleSession(messageID: messageID)

        guard
            let messageID,
            let session = controller.sessionRegistry.session(for: messageID),
            let message = controller.conversationCoordinator.findMessage(byId: messageID),
            controller.currentConversation?.id == session.conversationID
        else {
            controller.draftMessage = nil
            clearVisibleState(clearDraft: false)
            return
        }

        controller.draftMessage = message
        syncVisibleState(from: session)
        controller.conversationCoordinator.upsertMessage(message)
    }

    func detachVisibleSessionBinding() {
        controller.sessionRegistry.bindVisibleSession(messageID: nil)
        controller.draftMessage = nil
        clearVisibleState(clearDraft: false)
        controller.errorMessage = nil
    }

    func syncVisibleState(from session: ReplySession) {
        Task { @MainActor in
            guard visibleSessionMessageID == session.messageID else { return }
            guard let runtimeState = await runtimeState(for: session) else { return }

            let state = SessionVisibilityCoordinator.visibleState(
                from: session,
                runtimeState: runtimeState,
                draftMessage: controller.conversationCoordinator.findMessage(byId: session.messageID)
            )
            applyVisibleState(state)
        }
    }

    func refreshVisibleBindingForCurrentConversation() {
        guard let conversation = controller.currentConversation else {
            detachVisibleSessionBinding()
            return
        }

        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { controller.sessionRegistry.session(for: $0.id) != nil }) {
            bindVisibleSession(messageID: message.id)
            return
        }

        if let message = activeMessages.last {
            controller.sessionRegistry.bindVisibleSession(messageID: nil)
            clearVisibleState(clearDraft: false)
            controller.draftMessage = message
        } else {
            detachVisibleSessionBinding()
        }
    }

    func applyVisibleState(_ state: ChatVisibleSessionState) {
        controller.draftMessage = state.draftMessage
        controller.currentStreamingText = state.currentStreamingText
        controller.currentThinkingText = state.currentThinkingText
        controller.activeToolCalls = state.activeToolCalls
        controller.liveCitations = state.liveCitations
        controller.liveFilePathAnnotations = state.liveFilePathAnnotations
        controller.lastSequenceNumber = state.lastSequenceNumber
        controller.activeRequestModel = state.activeRequestModel
        controller.activeRequestEffort = state.activeRequestEffort
        controller.activeRequestUsesBackgroundMode = state.activeRequestUsesBackgroundMode
        controller.activeRequestServiceTier = state.activeRequestServiceTier
        controller.isStreaming = state.isStreaming
        controller.isThinking = state.isThinking
        controller.isRecovering = state.isRecovering
    }

    func clearLiveGenerationState(clearDraft: Bool) {
        clearVisibleState(clearDraft: clearDraft)
    }

    private var visibleSessionMessageID: UUID? {
        controller.sessionRegistry.visibleMessageID
    }

    private func clearVisibleState(clearDraft: Bool) {
        applyVisibleState(
            SessionVisibilityCoordinator.clearedState(
                retaining: controller.draftMessage,
                clearDraft: clearDraft
            )
        )
    }
}
