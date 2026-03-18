import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func saveSessionIfNeeded(_ session: ReplySession) {
        guard cachedRuntimeState(for: session) != nil else { return }
        let now = Date()
        let minimumInterval = session.request.usesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(session.lastDraftSaveTime) >= minimumInterval else { return }
        saveSessionNow(session)
    }

    func saveSessionNow(_ session: ReplySession) {
        guard let message = controller.conversationCoordinator.findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session) else { return }

        controller.messagePersistence.saveDraftState(from: .init(session: session, runtimeState: runtimeState), to: message)
        session.lastDraftSaveTime = Date()
        controller.conversationCoordinator.saveContextIfPossible("saveSessionNow")

        if message.conversation?.id == controller.currentConversation?.id {
            controller.conversationCoordinator.upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    func finalizeSession(_ session: ReplySession) {
        guard let message = controller.conversationCoordinator.findMessage(byId: session.messageID),
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
        controller.sessionRegistry.updateRuntimeState(normalizedRuntimeState, for: session.messageID)
        controller.messagePersistence.finalizeCompletedSession(
            from: .init(session: session, runtimeState: normalizedRuntimeState),
            to: message
        )
        controller.conversationCoordinator.upsertMessage(message)
        controller.conversationCoordinator.saveContextIfPossible("finalizeSession")
        controller.fileInteractionCoordinator.prefetchGeneratedFilesIfNeeded(for: message)

        let finishedConversation = message.conversation
        let wasVisible = controller.visibleSessionMessageID == session.messageID

        removeSession(session)

        if let finishedConversation,
           finishedConversation.title == "New Chat",
           finishedConversation.messages.count >= 2 {
            let viewModel = controller
            Task { @MainActor in
                await viewModel.generateTitleIfNeeded(for: finishedConversation)
            }
        }

        if wasVisible {
            controller.hapticService.notify(.success, isEnabled: controller.hapticsEnabled)
        }
    }

    func finalizeSessionAsPartial(_ session: ReplySession) {
        guard let message = controller.conversationCoordinator.findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session) else {
            removeSession(session)
            return
        }

        controller.messagePersistence.finalizePartialSession(
            from: .init(session: session, runtimeState: runtimeState),
            to: message
        )
        controller.conversationCoordinator.upsertMessage(message)
        controller.conversationCoordinator.saveContextIfPossible("finalizeSessionAsPartial")
        controller.fileInteractionCoordinator.prefetchGeneratedFilesIfNeeded(for: message)
        removeSession(session)
    }

    func removeEmptyMessage(_ message: Message, for session: ReplySession) {
        if let conversation = message.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        if let idx = controller.messages.firstIndex(where: { $0.id == message.id }) {
            controller.messages.remove(at: idx)
        }

        controller.conversationRepository.delete(message)
        controller.conversationCoordinator.saveContextIfPossible("removeEmptyMessage")
        removeSession(session)
    }

    func removeSession(_ session: ReplySession) {
        let wasVisible = controller.visibleSessionMessageID == session.messageID
        controller.sessionRegistry.remove(session) { target in
            target.task?.cancel()
            target.service.cancelStream()
        }
        removeRuntimeSession(for: session)

        if wasVisible {
            refreshVisibleBindingForCurrentConversation()
        }
    }
}
