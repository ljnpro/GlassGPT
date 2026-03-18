import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation

@MainActor
extension ChatController {
    func saveSessionIfNeeded(_ session: ReplySession) {
        guard cachedRuntimeState(for: session) != nil else { return }
        let now = Date()
        let minimumInterval = session.request.usesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(session.lastDraftSaveTime) >= minimumInterval else { return }
        saveSessionNow(session)
    }

    func saveSessionNow(_ session: ReplySession) {
        guard let message = findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session) else { return }

        messagePersistence.saveDraftState(from: .init(session: session, runtimeState: runtimeState), to: message)
        session.lastDraftSaveTime = Date()
        saveContextIfPossible("saveSessionNow")

        if message.conversation?.id == currentConversation?.id {
            upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    func finalizeSession(_ session: ReplySession) {
        guard let message = findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session) else {
            removeSession(session)
            return
        }

        let finalText = runtimeState.buffer.text
        let finalThinking = runtimeState.buffer.thinking.isEmpty ? nil : runtimeState.buffer.thinking

        if finalText.isEmpty {
            removeEmptyMessage(message, for: session)
            return
        }

        let normalizedRuntimeState = ReplyRuntimeState(
            assistantReplyID: runtimeState.assistantReplyID,
            messageID: runtimeState.messageID,
            conversationID: runtimeState.conversationID,
            lifecycle: runtimeState.lifecycle,
            buffer: ReplyBuffer(
                text: finalText,
                thinking: finalThinking ?? "",
                toolCalls: runtimeState.buffer.toolCalls,
                citations: runtimeState.buffer.citations,
                filePathAnnotations: runtimeState.buffer.filePathAnnotations,
                attachments: runtimeState.buffer.attachments
            ),
            isThinking: false
        )
        sessionRegistry.updateRuntimeState(normalizedRuntimeState, for: session.messageID)
        messagePersistence.finalizeCompletedSession(
            from: .init(session: session, runtimeState: normalizedRuntimeState),
            to: message
        )
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
        guard let message = findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session) else {
            removeSession(session)
            return
        }

        messagePersistence.finalizePartialSession(
            from: .init(session: session, runtimeState: runtimeState),
            to: message
        )
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
}
