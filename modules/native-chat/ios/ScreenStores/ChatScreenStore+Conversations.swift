import Foundation

@MainActor
extension ChatScreenStore {

    // MARK: - New Chat

    func startNewChat() {
        if let session = currentVisibleSession {
            saveSessionNow(session)
        }

        detachVisibleSessionBinding()
        currentConversation = nil
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        selectedImageData = nil
        pendingAttachments = []
        isThinking = false
        setVisibleRecoveryPhase(.idle)
        draftMessage = nil
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestUsesBackgroundMode = false
        filePreviewItem = nil
        sharedGeneratedFileItem = nil
        fileDownloadError = nil
        loadDefaultsFromSettings()
        syncConversationProjection()
        HapticService.shared.selection()
    }

    // MARK: - Regenerate Last Response

    func regenerateMessage(_ message: Message) {
        guard !isStreaming else { return }
        guard message.role == .assistant else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }

        if let conversation = currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        conversationRepository.delete(message)
        saveContextIfPossible("regenerateMessage.deleteOriginal")

        errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = currentConversation
        currentConversation?.messages.append(draft)
        saveContextIfPossible("regenerateMessage.insertDraft")

        guard let session = makeStreamingSession(for: draft) else {
            errorMessage = "Failed to start response session."
            return
        }

        registerSession(session, visible: true)
        session.beginSubmitting()
        syncVisibleState(from: session)

        HapticService.shared.impact(.medium)

        startStreamingRequest(for: session)
    }

    // MARK: - Load Conversation

    func loadConversation(_ conversation: Conversation) {
        if let session = currentVisibleSession {
            saveSessionNow(session)
        }

        detachVisibleSessionBinding()
        currentConversation = conversation
        messages = visibleMessages(for: conversation)
        syncConversationProjection()

        applyConversationConfiguration(from: conversation)

        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        isThinking = false
        setVisibleRecoveryPhase(.idle)
        draftMessage = nil
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestUsesBackgroundMode = false
        pendingAttachments = []
        filePreviewItem = nil
        sharedGeneratedFileItem = nil
        fileDownloadError = nil

        refreshVisibleBindingForCurrentConversation()

        Task { @MainActor in
            await recoverIncompleteMessagesInCurrentConversation()
        }
    }

    // MARK: - Restore Last Conversation

    func restoreLastConversationIfAvailable() {
        do {
            if let lastConversation = try conversationRepository.fetchMostRecentConversationWithMessages() {
                currentConversation = lastConversation
                messages = visibleMessages(for: lastConversation)

                applyConversationConfiguration(from: lastConversation)

                #if DEBUG
                Loggers.chat.debug("[Restore] Loaded last conversation: \(lastConversation.title) (\(messages.count) messages)")
                #endif
            }
        } catch {
            Loggers.persistence.error("[restoreLastConversationIfAvailable] \(error.localizedDescription)")
        }
    }
    func activeIncompleteAssistantDraft() -> Message? {
        if let draft = draftMessage, !draft.isComplete, draft.role == .assistant {
            return draft
        }

        return currentConversation?.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }
}
