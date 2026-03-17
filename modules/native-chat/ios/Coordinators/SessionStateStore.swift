import Foundation

@MainActor
final class SessionStateStore {
    unowned let viewModel: ChatViewModel
    let registry = ChatSessionRegistry()

    init(viewModel: ChatViewModel) {
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

    func finalizeSession(_ session: ResponseSession) {
        guard let message = viewModel.findMessage(byId: session.messageID) else {
            removeSession(session)
            return
        }

        let finalText = session.currentText
        let finalThinking = session.currentThinking.isEmpty ? nil : session.currentThinking

        if finalText.isEmpty {
            removeEmptyMessage(message, for: session)
            return
        }

        session.currentText = finalText
        session.currentThinking = finalThinking ?? ""
        viewModel.messagePersistence.finalizeCompletedSession(from: session, to: message)
        viewModel.upsertMessage(message)
        viewModel.saveContextIfPossible("finalizeSession")
        viewModel.prefetchGeneratedFilesIfNeeded(for: message)

        let finishedConversation = message.conversation
        let wasVisible = viewModel.visibleSessionMessageID == session.messageID

        removeSession(session)

        if let finishedConversation,
           finishedConversation.title == "New Chat",
           finishedConversation.messages.count >= 2 {
            Task { @MainActor in
                await self.viewModel.generateTitleIfNeeded(for: finishedConversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }

    func finalizeSessionAsPartial(_ session: ResponseSession) {
        guard let message = viewModel.findMessage(byId: session.messageID) else {
            removeSession(session)
            return
        }

        viewModel.messagePersistence.finalizePartialSession(from: session, to: message)
        viewModel.upsertMessage(message)
        viewModel.saveContextIfPossible("finalizeSessionAsPartial")
        viewModel.prefetchGeneratedFilesIfNeeded(for: message)
        removeSession(session)
    }

    func removeEmptyMessage(_ message: Message, for session: ResponseSession) {
        if let conversation = message.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
            viewModel.messages.remove(at: idx)
        }

        viewModel.conversationRepository.delete(message)
        viewModel.saveContextIfPossible("removeEmptyMessage")
        removeSession(session)
    }

    func removeSession(_ session: ResponseSession) {
        let wasVisible = viewModel.visibleSessionMessageID == session.messageID
        registry.remove(session) { target in
            target.task?.cancel()
            target.service.cancelStream()
        }

        if wasVisible {
            refreshVisibleBindingForCurrentConversation()
        }
    }

    func refreshVisibleBindingForCurrentConversation() {
        guard let conversation = viewModel.currentConversation else {
            detachVisibleSessionBinding()
            return
        }

        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { registry.session(for: $0.id) != nil }) {
            bindVisibleSession(messageID: message.id)
            return
        }

        if let message = activeMessages.last {
            registry.bindVisibleSession(messageID: nil)
            clearVisibleState(clearDraft: false)
            viewModel.draftMessage = message
        } else {
            detachVisibleSessionBinding()
        }
    }

    func suspendActiveSessionsForAppBackground() {
        let sessions = registry.allSessions
        guard !sessions.isEmpty else { return }

        for session in sessions {
            saveSessionNow(session)
            session.cancelStreaming()
            session.service.cancelStream()
            session.task?.cancel()

            guard let message = viewModel.findMessage(byId: session.messageID) else { continue }

            if session.responseId != nil {
                message.isComplete = false
                message.conversation?.updatedAt = .now
                viewModel.upsertMessage(message)
            } else {
                message.content = viewModel.interruptedResponseFallbackText(for: message, session: session)
                message.thinking = session.currentThinking.isEmpty ? nil : session.currentThinking
                message.isComplete = true
                message.lastSequenceNumber = nil
                message.conversation?.updatedAt = .now
                viewModel.upsertMessage(message)
            }
        }

        viewModel.saveContextIfPossible("suspendActiveSessionsForAppBackground")
        registry.removeAll { session in
            session.task?.cancel()
            session.service.cancelStream()
        }
        detachVisibleSessionBinding()
    }

    func clearLiveGenerationState(clearDraft: Bool) {
        clearVisibleState(clearDraft: clearDraft)
    }

    private func setVisibleRecoveryPhase(_ phase: RecoveryPhase) {
        viewModel.visibleRecoveryPhase = phase
        viewModel.isRecovering = phase == .streamResuming
    }

    private func clearVisibleState(clearDraft: Bool) {
        viewModel.applyVisibleState(
            SessionVisibilityCoordinator.clearedState(
                retaining: viewModel.draftMessage,
                clearDraft: clearDraft
            )
        )
    }
}
