import Foundation

@MainActor
extension ChatViewModel {
    func recoverIncompleteMessages() async {
        guard !apiKey.isEmpty else { return }

        await cleanupStaleDrafts()

        let fetchedMessages: [Message]
        do {
            fetchedMessages = try draftRepository.fetchRecoverableDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch recoverable drafts: \(error.localizedDescription)")
            return
        }

        let activeDraftID = activeIncompleteAssistantDraft()?.id
        let currentConversationID = currentConversation?.id
        let incompleteMessages = fetchedMessages.filter {
            $0.id != activeDraftID && $0.conversation?.id != currentConversationID
        }
        guard !incompleteMessages.isEmpty else { return }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Found \(incompleteMessages.count) incomplete message(s) to recover")
        #endif

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    func cleanupStaleDrafts() async {
        let staleThreshold = Date().addingTimeInterval(-24 * 60 * 60)
        let staleMessages: [Message]

        do {
            staleMessages = try draftRepository.fetchIncompleteDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch stale drafts: \(error.localizedDescription)")
            return
        }

        var cleanedCount = 0

        for message in staleMessages {
            guard message.createdAt < staleThreshold else { continue }

            if message.content.isEmpty && message.responseId == nil {
                conversationRepository.delete(message)
                cleanedCount += 1
            } else {
                message.isComplete = true
                if message.content.isEmpty {
                    message.content = "[Response interrupted. Please try again.]"
                }
                cleanedCount += 1
            }
        }

        if cleanedCount > 0 {
            saveContextIfPossible("cleanupStaleDrafts")
            #if DEBUG
            Loggers.recovery.debug("[Recovery] Cleaned up \(cleanedCount) stale draft(s)")
            #endif
        }
    }

    func resendOrphanedDrafts() async {
        guard !apiKey.isEmpty else { return }

        let orphanedDrafts: [Message]
        do {
            orphanedDrafts = try draftRepository.fetchOrphanedDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch orphaned drafts: \(error.localizedDescription)")
            return
        }

        let draftsToResend = orphanedDrafts.filter { $0.role == .assistant && $0.content.isEmpty }

        #if DEBUG
        if !draftsToResend.isEmpty {
            Loggers.recovery.debug("[Recovery] Found \(draftsToResend.count) orphaned draft(s) to resend")
        }
        #endif

        let currentConversationID = currentConversation?.id

        for draft in draftsToResend {
            guard let conversation = draft.conversation else {
                conversationRepository.delete(draft)
                saveContextIfPossible("resendOrphanedDrafts.deleteDetachedDraft")
                continue
            }

            if let currentConversationID, conversation.id != currentConversationID {
                continue
            }

            let userMessages = conversation.messages
                .filter { $0.role == .user }
                .sorted { $0.createdAt < $1.createdAt }

            guard userMessages.last != nil else {
                conversationRepository.delete(draft)
                saveContextIfPossible("resendOrphanedDrafts.deleteDraftWithoutUserMessage")
                continue
            }

            #if DEBUG
            Loggers.recovery.debug("[Recovery] Resending request for orphaned draft in conversation: \(conversation.title)")
            #endif

            currentConversation = conversation
            messages = visibleMessages(for: conversation)
                .filter { $0.id != draft.id }

            applyConversationConfiguration(from: conversation)

            if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: idx)
            }

            conversationRepository.delete(draft)
            saveContextIfPossible("resendOrphanedDrafts.deleteBeforeRestart")

            let newDraft = Message(
                role: .assistant,
                content: "",
                thinking: nil,
                lastSequenceNumber: nil,
                usedBackgroundMode: backgroundModeEnabled,
                isComplete: false
            )
            newDraft.conversation = currentConversation
            currentConversation?.messages.append(newDraft)
            saveContextIfPossible("resendOrphanedDrafts.insertReplacementDraft")

            guard let session = makeStreamingSession(for: newDraft) else {
                errorMessage = "Failed to restart orphaned draft."
                return
            }

            registerSession(session, visible: true)
            session.isStreaming = true
            session.isThinking = true
            setRecoveryPhase(.idle, for: session)
            syncVisibleState(from: session)
            errorMessage = nil

            #if DEBUG
            Loggers.recovery.debug("[Recovery] Starting resend stream for conversation: \(conversation.title), messages count: \(messages.count)")
            #endif

            startStreamingRequest(for: session)
            return
        }
    }

    func recoverIncompleteMessagesInCurrentConversation() async {
        guard !apiKey.isEmpty else { return }
        guard let conversation = currentConversation else { return }

        let incompleteMessages = conversation.messages.filter {
            $0.role == .assistant && !$0.isComplete && $0.responseId != nil
        }

        guard !incompleteMessages.isEmpty else { return }

        let sortedMessages = incompleteMessages.sorted { $0.createdAt < $1.createdAt }

        if let activeMessage = sortedMessages.last,
           let responseId = activeMessage.responseId {
            recoverResponse(
                messageId: activeMessage.id,
                responseId: responseId,
                preferStreamingResume: activeMessage.usedBackgroundMode,
                visible: true
            )
        }

        for message in sortedMessages.dropLast() {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    func recoverSingleMessage(message: Message, responseId: String, visible: Bool) {
        recoverResponse(
            messageId: message.id,
            responseId: responseId,
            preferStreamingResume: message.usedBackgroundMode,
            visible: visible
        )
    }

    func findMessage(byId id: UUID) -> Message? {
        if let msg = messages.first(where: { $0.id == id }) {
            return msg
        }

        if let draft = draftMessage, draft.id == id {
            return draft
        }

        do {
            return try conversationRepository.fetchMessage(id: id)
        } catch {
            Loggers.persistence.error("[findMessage] \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func detachBackgroundResponseIfPossible(reason: String) -> Bool {
        guard
            let session = currentVisibleSession,
            let draft = draftMessage,
            ChatSessionDecisions.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: draft.usedBackgroundMode,
                responseId: draft.responseId
            )
        else {
            return false
        }

        saveSessionNow(session)
        errorMessage = nil
        detachVisibleSessionBinding()
        endBackgroundTask()

        #if DEBUG
        Loggers.chat.debug("[Detach] Detached background response for \(reason)")
        #endif

        return true
    }
}
