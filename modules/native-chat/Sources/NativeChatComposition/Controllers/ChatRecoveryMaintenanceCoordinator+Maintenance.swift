import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatRecoveryMaintenanceCoordinator {
    func recoverIncompleteMessages() async {
        let apiKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else { return }

        await cleanupStaleDrafts()

        let fetchedMessages: [Message]
        do {
            fetchedMessages = try services.draftRepository.fetchRecoverableDrafts(mode: .chat)
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch recoverable drafts: \(error.localizedDescription)")
            return
        }

        let activeDraftID = conversations.activeIncompleteAssistantDraft()?.id
        let currentConversationID = state.currentConversation?.id
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
            staleMessages = try services.draftRepository.fetchIncompleteDrafts(mode: .chat)
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch stale drafts: \(error.localizedDescription)")
            return
        }

        var cleanedCount = 0

        for message in staleMessages {
            guard message.createdAt < staleThreshold else { continue }

            if message.content.isEmpty, message.responseId == nil {
                services.conversationRepository.delete(message)
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
            conversations.saveContextIfPossible("cleanupStaleDrafts")
            #if DEBUG
            Loggers.recovery.debug("[Recovery] Cleaned up \(cleanedCount) stale draft(s)")
            #endif
        }
    }

    func resendOrphanedDrafts() async {
        let apiKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else { return }

        let orphanedDrafts: [Message]
        do {
            orphanedDrafts = try services.draftRepository.fetchOrphanedDrafts(mode: .chat)
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch orphaned drafts: \(error.localizedDescription)")
            return
        }

        let draftsToResend = orphanedDrafts.filter { $0.role == .assistant }

        #if DEBUG
        if !draftsToResend.isEmpty {
            Loggers.recovery.debug("[Recovery] Found \(draftsToResend.count) orphaned draft(s) to resend")
        }
        #endif

        let currentConversationID = state.currentConversation?.id

        for draft in draftsToResend {
            if restartOrphanedDraftIfEligible(draft, currentConversationID: currentConversationID) {
                return
            }
        }
    }

    private func restartOrphanedDraftIfEligible(
        _ draft: Message,
        currentConversationID: UUID?
    ) -> Bool {
        guard let conversation = resendableConversation(for: draft, currentConversationID: currentConversationID) else {
            return false
        }

        let newDraft = replaceOrphanedDraft(draft, in: conversation)
        guard let preparedReply = prepareRestartReply(for: newDraft) else {
            return true
        }

        startResentDraftSession(preparedReply, conversation: conversation)
        return true
    }

    private func resendableConversation(
        for draft: Message,
        currentConversationID: UUID?
    ) -> Conversation? {
        guard let conversation = draft.conversation else {
            services.conversationRepository.delete(draft)
            conversations.saveContextIfPossible("resendOrphanedDrafts.deleteDetachedDraft")
            return nil
        }

        guard conversation.mode == .chat else {
            return nil
        }

        if let currentConversationID, conversation.id != currentConversationID {
            return nil
        }

        let hasUserMessage = conversation.messages.contains { $0.role == .user }
        guard hasUserMessage else {
            services.conversationRepository.delete(draft)
            conversations.saveContextIfPossible("resendOrphanedDrafts.deleteDraftWithoutUserMessage")
            return nil
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Resending request for orphaned draft in conversation: \(conversation.title)")
        #endif
        return conversation
    }

    private func replaceOrphanedDraft(_ draft: Message, in conversation: Conversation) -> Message {
        state.currentConversation = conversation
        state.messages = conversations.visibleMessages(for: conversation)
            .filter { $0.id != draft.id }
        conversations.applyConversationConfiguration(from: conversation)

        if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
            conversation.messages.remove(at: idx)
        }

        services.conversationRepository.delete(draft)
        conversations.saveContextIfPossible("resendOrphanedDrafts.deleteBeforeRestart")

        let newDraft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: state.backgroundModeEnabled,
            isComplete: false
        )
        newDraft.conversation = state.currentConversation
        state.currentConversation?.messages.append(newDraft)
        conversations.saveContextIfPossible("resendOrphanedDrafts.insertReplacementDraft")
        return newDraft
    }

    private func prepareRestartReply(for draft: Message) -> PreparedAssistantReply? {
        do {
            return try drafts.prepareExistingDraft(draft)
        } catch SendMessagePreparationError.missingAPIKey {
            state.errorMessage = "Please add your OpenAI API key in Settings."
            return nil
        } catch {
            state.errorMessage = "Failed to restart orphaned draft."
            return nil
        }
    }

    private func startResentDraftSession(
        _ preparedReply: PreparedAssistantReply,
        conversation: Conversation
    ) {
        let session = ReplySession(preparedReply: preparedReply)
        sessions.registerSession(
            session,
            execution: SessionExecutionState(service: services.serviceFactory()),
            visible: true,
            syncIfCurrentlyVisible: true
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await sessions.applyRuntimeTransition(.beginSubmitting, to: session)
            _ = await sessions.applyRuntimeTransition(.setThinking(true), to: session)
            sessions.syncVisibleState(from: session)
        }
        state.errorMessage = nil

        #if DEBUG
        Loggers.recovery.debug(
            "[Recovery] Starting resend stream for \(conversation.title), messages: \(state.messages.count)"
        )
        #endif

        streaming.startStreamingRequest(for: session, reconnectAttempt: 0)
    }
}
