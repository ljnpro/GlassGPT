import Foundation

@MainActor
final class SessionProjectionStore {
    unowned let viewModel: ChatScreenStore
    let registry = ChatSessionRegistry()

    init(viewModel: ChatScreenStore) {
        self.viewModel = viewModel
    }

    func makeStreamingSession(for draft: Message) -> ResponseSession? {
        guard let conversation = draft.conversation else { return nil }
        let requestMessages = viewModel.buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = viewModel.sessionRequestConfiguration(for: conversation)

        return ResponseSession(
            message: draft,
            conversationID: conversation.id,
            service: viewModel.serviceFactory(),
            requestMessages: requestMessages,
            requestModel: configuration.0,
            requestEffort: configuration.1,
            requestUsesBackgroundMode: conversation.backgroundModeEnabled,
            requestServiceTier: configuration.2
        )
    }

    func makeRecoverySession(for message: Message) -> ResponseSession? {
        guard let conversation = message.conversation else { return nil }
        let configuration = viewModel.sessionRequestConfiguration(for: conversation)

        return ResponseSession(
            message: message,
            conversationID: conversation.id,
            service: viewModel.serviceFactory(),
            requestMessages: nil,
            requestModel: configuration.0,
            requestEffort: configuration.1,
            requestUsesBackgroundMode: message.usedBackgroundMode,
            requestServiceTier: configuration.2
        )
    }

    func registerSession(_ session: ResponseSession, visible: Bool) {
        registry.register(session, visible: visible) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        if visible {
            bindVisibleSession(messageID: session.messageID)
        } else if viewModel.visibleSessionMessageID == session.messageID {
            syncVisibleState(from: session)
        }
    }

    func isSessionActive(_ session: ResponseSession) -> Bool {
        registry.contains(session)
    }

    func bindVisibleSession(messageID: UUID?) {
        registry.bindVisibleSession(messageID: messageID)

        guard
            let messageID,
            let session = registry.session(for: messageID),
            let message = viewModel.findMessage(byId: messageID),
            viewModel.currentConversation?.id == session.conversationID
        else {
            viewModel.draftMessage = nil
            clearVisibleState(clearDraft: false)
            return
        }

        viewModel.draftMessage = message
        syncVisibleState(from: session)
        viewModel.upsertMessage(message)
    }

    func detachVisibleSessionBinding() {
        registry.bindVisibleSession(messageID: nil)
        viewModel.draftMessage = nil
        clearVisibleState(clearDraft: false)
        viewModel.errorMessage = nil
    }

    func setRecoveryPhase(_ phase: RecoveryPhase, for session: ResponseSession) {
        session.setRecoveryPhase(phase)
        if viewModel.visibleSessionMessageID == session.messageID {
            setVisibleRecoveryPhase(phase)
        }
    }

    func syncVisibleState(from session: ResponseSession) {
        guard viewModel.visibleSessionMessageID == session.messageID else { return }

        let state = SessionVisibilityCoordinator.visibleState(
            from: session,
            draftMessage: viewModel.findMessage(byId: session.messageID)
        )
        viewModel.applyVisibleState(state)
    }

    func saveSessionIfNeeded(_ session: ResponseSession) {
        let now = Date()
        let minimumInterval = session.requestUsesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(session.lastDraftSaveTime) >= minimumInterval else { return }
        saveSessionNow(session)
    }

    func saveSessionNow(_ session: ResponseSession) {
        guard let message = viewModel.findMessage(byId: session.messageID) else { return }

        viewModel.messagePersistence.saveDraftState(from: session, to: message)
        session.lastDraftSaveTime = Date()
        viewModel.saveContextIfPossible("saveSessionNow")

        if message.conversation?.id == viewModel.currentConversation?.id {
            viewModel.upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    func clearLiveGenerationState(clearDraft: Bool) {
        clearVisibleState(clearDraft: clearDraft)
    }

    private func setVisibleRecoveryPhase(_ phase: RecoveryPhase) {
        viewModel.visibleRecoveryPhase = phase
        viewModel.isRecovering = phase == .streamResuming
    }

    func clearVisibleState(clearDraft: Bool) {
        viewModel.applyVisibleState(
            SessionVisibilityCoordinator.clearedState(
                retaining: viewModel.draftMessage,
                clearDraft: clearDraft
            )
        )
    }
}
