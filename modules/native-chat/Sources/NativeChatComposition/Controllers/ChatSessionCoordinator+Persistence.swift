import ChatPersistenceCore
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
        guard let message = conversations.findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session) else { return }

        services.messagePersistence.saveDraftState(from: .init(session: session, runtimeState: runtimeState), to: message)
        session.lastDraftSaveTime = Date()
        conversations.saveContextIfPossible("saveSessionNow")

        if message.conversation?.id == state.currentConversation?.id {
            conversations.upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    func finalizeSession(_ session: ReplySession) {
        guard let message = conversations.findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session)
        else {
            removeSession(session)
            return
        }

        let finalText = runtimeState.buffer.text
        let finalThinking = runtimeState.buffer.thinking.isEmpty ? nil : runtimeState.buffer.thinking

        if finalText.isEmpty {
            removeEmptyMessage(message, for: session)
            return
        }

        let normalizedRuntimeState = normalizedCompletedRuntimeState(
            from: runtimeState,
            finalText: finalText,
            finalThinking: finalThinking
        )
        services.sessionRegistry.updateRuntimeState(normalizedRuntimeState, for: session.messageID)
        services.messagePersistence.finalizeCompletedSession(
            from: .init(session: session, runtimeState: normalizedRuntimeState),
            to: message
        )
        conversations.upsertMessage(message)
        conversations.saveContextIfPossible("finalizeSession")

        let finishedConversation = message.conversation
        let wasVisible = visibleSessionMessageID == session.messageID

        removeSession(session)
        files.prefetchGeneratedFilesIfNeeded(for: message)
        scheduleTitleGenerationIfNeeded(for: finishedConversation)

        if wasVisible {
            state.hapticService.notify(.success, isEnabled: state.hapticsEnabled)
        }
    }

    func finalizeSessionAsPartial(_ session: ReplySession) {
        guard let message = conversations.findMessage(byId: session.messageID),
              let runtimeState = cachedRuntimeState(for: session)
        else {
            removeSession(session)
            return
        }

        services.messagePersistence.finalizePartialSession(
            from: .init(session: session, runtimeState: runtimeState),
            to: message
        )
        conversations.upsertMessage(message)
        conversations.saveContextIfPossible("finalizeSessionAsPartial")
        removeSession(session)
        files.prefetchGeneratedFilesIfNeeded(for: message)
    }

    func removeEmptyMessage(_ message: Message, for session: ReplySession) {
        if let conversation = message.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        if let idx = state.messages.firstIndex(where: { $0.id == message.id }) {
            state.messages.remove(at: idx)
        }

        services.conversationRepository.delete(message)
        conversations.saveContextIfPossible("removeEmptyMessage")
        removeSession(session)
    }

    func removeSession(_ session: ReplySession) {
        let wasVisible = visibleSessionMessageID == session.messageID
        services.cancelGeneratedFilePrefetches(
            services.generatedFilePrefetchRegistry.cancel(messageID: session.messageID)
        )
        services.sessionRegistry.remove(session) { target in
            target.task?.cancel()
            target.service.cancelStream()
        }
        removeRuntimeSession(for: session)

        if wasVisible {
            refreshVisibleBindingForCurrentConversation()
        }
    }

    private func normalizedCompletedRuntimeState(
        from runtimeState: ReplyRuntimeState,
        finalText: String,
        finalThinking: String?
    ) -> ReplyRuntimeState {
        ReplyRuntimeState(
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
    }

    private func scheduleTitleGenerationIfNeeded(for conversation: Conversation?) {
        guard let conversation,
              conversation.title == "New Chat",
              conversation.messages.count >= 2
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let apiKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await generateConversationTitleIfNeeded(
                for: conversation,
                apiKey: apiKey,
                openAIService: services.openAIService,
                saveContext: { self.conversations.saveContextIfPossible($0) }
            )
        }
    }
}
