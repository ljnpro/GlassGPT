import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation

@MainActor
extension ChatController {
    func saveSessionIfNeeded(_ session: ReplySession) {
        let now = Date()
        let minimumInterval = session.request.usesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(session.lastDraftSaveTime) >= minimumInterval else { return }
        saveSessionNow(session)
    }

    func saveSessionNow(_ session: ReplySession) {
        guard let message = findMessage(byId: session.messageID) else { return }

        messagePersistence.saveDraftState(from: .init(session), to: message)
        session.lastDraftSaveTime = Date()
        saveContextIfPossible("saveSessionNow")
        syncRuntimeSession(from: session)

        if message.conversation?.id == currentConversation?.id {
            upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    func finalizeSession(_ session: ReplySession) {
        guard let message = findMessage(byId: session.messageID) else {
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
        messagePersistence.finalizeCompletedSession(from: .init(session), to: message)
        upsertMessage(message)
        saveContextIfPossible("finalizeSession")
        prefetchGeneratedFilesIfNeeded(for: message)

        let finishedConversation = message.conversation
        let wasVisible = visibleSessionMessageID == session.messageID

        removeSession(session)

        if let finishedConversation,
           finishedConversation.title == "New Chat",
           finishedConversation.messages.count >= 2 {
            let viewModel = self
            Task { @MainActor in
                await viewModel.generateTitleIfNeeded(for: finishedConversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }

    func finalizeSessionAsPartial(_ session: ReplySession) {
        guard let message = findMessage(byId: session.messageID) else {
            removeSession(session)
            return
        }

        messagePersistence.finalizePartialSession(from: .init(session), to: message)
        upsertMessage(message)
        saveContextIfPossible("finalizeSessionAsPartial")
        prefetchGeneratedFilesIfNeeded(for: message)
        removeSession(session)
    }

    func removeEmptyMessage(_ message: Message, for session: ReplySession) {
        if let conversation = message.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: idx)
        }

        conversationRepository.delete(message)
        saveContextIfPossible("removeEmptyMessage")
        removeSession(session)
    }

    func removeSession(_ session: ReplySession) {
        let wasVisible = visibleSessionMessageID == session.messageID
        sessionRegistry.remove(session) { target in
            target.task?.cancel()
            target.service.cancelStream()
        }
        removeRuntimeSession(for: session)

        if wasVisible {
            refreshVisibleBindingForCurrentConversation()
        }
    }

    func visibleMessages(for conversation: Conversation) -> [Message] {
        conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { !shouldHideMessage($0) }
    }

    func shouldHideMessage(_ message: Message) -> Bool {
        guard message.role == .assistant, !message.isComplete else {
            return false
        }

        if message.responseId != nil {
            return false
        }

        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if let thinking = message.thinking,
           !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if !message.toolCalls.isEmpty || !message.annotations.isEmpty || !message.filePathAnnotations.isEmpty {
            return false
        }

        return true
    }

    func syncConversationConfiguration() {
        guard let currentConversation else { return }
        currentConversation.model = selectedModel.rawValue
        currentConversation.reasoningEffort = reasoningEffort.rawValue
        currentConversation.backgroundModeEnabled = backgroundModeEnabled
        currentConversation.serviceTierRawValue = serviceTier.rawValue
        currentConversation.updatedAt = .now
        saveContextIfPossible("syncConversationConfiguration")
    }

    func upsertMessage(_ message: Message) {
        guard message.conversation?.id == currentConversation?.id else {
            return
        }

        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
            messages.sort { $0.createdAt < $1.createdAt }
        }
    }
}
