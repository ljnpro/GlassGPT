import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func makeRecoverySession(for message: Message) -> ReplySession? {
        guard let conversation = message.conversation else { return nil }
        return ChatRecoverySessionFactory.makeSession(
            for: message,
            conversationID: conversation.id,
            configuration: conversations.sessionRequestConfiguration(for: conversation),
            apiKey: services.apiKeyStore.loadAPIKey() ?? ""
        )
    }

    func registerSession(_ session: ReplySession, execution: SessionExecutionState, visible: Bool) {
        services.sessionRegistry.register(session, execution: execution, visible: visible) { existing in
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
        services.sessionRegistry.contains(session)
    }

    func bindVisibleSession(messageID: UUID?) {
        services.sessionRegistry.bindVisibleSession(messageID: messageID)

        guard
            let messageID,
            let session = services.sessionRegistry.session(for: messageID),
            let message = conversations.findMessage(byId: messageID),
            state.currentConversation?.id == session.conversationID
        else {
            state.draftMessage = nil
            clearVisibleState(clearDraft: false)
            return
        }

        state.draftMessage = message
        syncVisibleState(from: session)
        conversations.upsertMessage(message)
    }

    func detachVisibleSessionBinding() {
        services.sessionRegistry.bindVisibleSession(messageID: nil)
        state.draftMessage = nil
        clearVisibleState(clearDraft: false)
        state.errorMessage = nil
    }

    func syncVisibleState(from session: ReplySession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard visibleSessionMessageID == session.messageID else { return }
            guard let runtimeState = await runtimeState(for: session) else { return }

            let state = SessionVisibilityCoordinator.visibleState(
                from: session,
                runtimeState: runtimeState,
                draftMessage: conversations.findMessage(byId: session.messageID)
            )
            applyVisibleState(state)
        }
    }

    func refreshVisibleBindingForCurrentConversation() {
        guard let conversation = state.currentConversation else {
            detachVisibleSessionBinding()
            return
        }

        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { services.sessionRegistry.session(for: $0.id) != nil }) {
            bindVisibleSession(messageID: message.id)
            return
        }

        if let message = activeMessages.last {
            services.sessionRegistry.bindVisibleSession(messageID: nil)
            clearVisibleState(clearDraft: false)
            state.draftMessage = message
        } else {
            detachVisibleSessionBinding()
        }
    }

    func applyVisibleState(_ state: ChatVisibleSessionState) {
        self.state.draftMessage = state.draftMessage
        self.state.currentStreamingText = state.currentStreamingText
        self.state.currentThinkingText = state.currentThinkingText
        self.state.activeToolCalls = state.activeToolCalls
        self.state.liveCitations = state.liveCitations
        self.state.liveFilePathAnnotations = state.liveFilePathAnnotations
        self.state.lastSequenceNumber = state.lastSequenceNumber
        self.state.activeRequestModel = state.activeRequestModel
        self.state.activeRequestEffort = state.activeRequestEffort
        self.state.activeRequestUsesBackgroundMode = state.activeRequestUsesBackgroundMode
        self.state.activeRequestServiceTier = state.activeRequestServiceTier
        self.state.isStreaming = state.isStreaming
        self.state.isThinking = state.isThinking
        self.state.isRecovering = state.isRecovering
    }

    func clearLiveGenerationState(clearDraft: Bool) {
        clearVisibleState(clearDraft: clearDraft)
    }

    private func clearVisibleState(clearDraft: Bool) {
        applyVisibleState(
            SessionVisibilityCoordinator.clearedState(
                retaining: state.draftMessage,
                clearDraft: clearDraft
            )
        )
    }
}
