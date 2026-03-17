import Foundation

@MainActor
extension ChatViewModel {

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
            if let lastConversation = try conversationRepository.fetchMostRecentConversation(),
               !lastConversation.messages.isEmpty {
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

    func generateTitlesForUntitledConversations() async {
        guard !apiKey.isEmpty else { return }

        let untitled: [Conversation]
        do {
            untitled = try conversationRepository.fetchUntitledConversations()
        } catch {
            Loggers.chat.error("[Title] Failed to fetch untitled conversations: \(error.localizedDescription)")
            return
        }

        for conversation in untitled {
            guard conversation.messages.count >= 2 else { continue }

            let preview = conversation.messages
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(4)
                .map { "\($0.roleRawValue): \($0.content.prefix(200))" }
                .joined(separator: "\n")

            do {
                let title = try await openAIService.generateTitle(
                    for: preview,
                    apiKey: apiKey
                )
                conversation.title = title
                saveContextIfPossible("generateTitlesForUntitledConversations")

                if conversation.id == currentConversation?.id {
                    currentConversation?.title = title
                }

                #if DEBUG
                Loggers.chat.debug("[Title] Generated title for conversation \(conversation.id): \(title)")
                #endif
            } catch {
                #if DEBUG
                Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func generateTitleIfNeeded(for conversation: Conversation) async {
        guard !apiKey.isEmpty else { return }
        guard conversation.title == "New Chat", conversation.messages.count >= 2 else { return }

        let preview = conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(4)
            .map { "\($0.roleRawValue): \($0.content.prefix(200))" }
            .joined(separator: "\n")

        do {
            let title = try await openAIService.generateTitle(
                for: preview,
                apiKey: apiKey
            )
            conversation.title = title
            saveContextIfPossible("generateTitleIfNeeded")
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
            #endif
        }
    }

    func generateTitle() async {
        guard let conversation = currentConversation else { return }

        let preview = messages.prefix(4).map { msg in
            "\(msg.role.rawValue): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

        do {
            let title = try await openAIService.generateTitle(
                for: preview,
                apiKey: apiKey
            )
            conversation.title = title
            saveContextIfPossible("generateTitle")
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
            #endif
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
