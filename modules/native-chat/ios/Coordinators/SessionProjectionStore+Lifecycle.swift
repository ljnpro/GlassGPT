import Foundation

extension SessionProjectionStore {
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
            let viewModel = self.viewModel
            Task { @MainActor in
                await viewModel.generateTitleIfNeeded(for: finishedConversation)
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
        viewModel.removeRuntimeSession(for: session)

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
}
