import ChatPersistenceSwiftData
import ChatDomain
import ChatPersistenceCore
import Foundation
import ChatRuntimeModel

@MainActor
extension ChatRecoveryMaintenanceCoordinator {
    func recoverIncompleteMessages() async {
        guard !controller.apiKey.isEmpty else { return }

        await cleanupStaleDrafts()

        let fetchedMessages: [Message]
        do {
            fetchedMessages = try controller.draftRepository.fetchRecoverableDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch recoverable drafts: \(error.localizedDescription)")
            return
        }

        let activeDraftID = controller.activeIncompleteAssistantDraft()?.id
        let currentConversationID = controller.currentConversation?.id
        let incompleteMessages = fetchedMessages.filter {
            $0.id != activeDraftID && $0.conversation?.id != currentConversationID
        }
        guard !incompleteMessages.isEmpty else { return }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Found \(incompleteMessages.count) incomplete message(s) to recover")
        #endif

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            controller.recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    func cleanupStaleDrafts() async {
        let staleThreshold = Date().addingTimeInterval(-24 * 60 * 60)
        let staleMessages: [Message]

        do {
            staleMessages = try controller.draftRepository.fetchIncompleteDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch stale drafts: \(error.localizedDescription)")
            return
        }

        var cleanedCount = 0

        for message in staleMessages {
            guard message.createdAt < staleThreshold else { continue }

            if message.content.isEmpty && message.responseId == nil {
                controller.conversationRepository.delete(message)
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
            controller.saveContextIfPossible("cleanupStaleDrafts")
            #if DEBUG
            Loggers.recovery.debug("[Recovery] Cleaned up \(cleanedCount) stale draft(s)")
            #endif
        }
    }

    func resendOrphanedDrafts() async {
        guard !controller.apiKey.isEmpty else { return }

        let orphanedDrafts: [Message]
        do {
            orphanedDrafts = try controller.draftRepository.fetchOrphanedDrafts()
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

        let currentConversationID = controller.currentConversation?.id

        for draft in draftsToResend {
            guard let conversation = draft.conversation else {
                controller.conversationRepository.delete(draft)
                controller.saveContextIfPossible("resendOrphanedDrafts.deleteDetachedDraft")
                continue
            }

            if let currentConversationID, conversation.id != currentConversationID {
                continue
            }

            let userMessages = conversation.messages
                .filter { $0.role == .user }
                .sorted { $0.createdAt < $1.createdAt }

            guard userMessages.last != nil else {
                controller.conversationRepository.delete(draft)
                controller.saveContextIfPossible("resendOrphanedDrafts.deleteDraftWithoutUserMessage")
                continue
            }

            #if DEBUG
            Loggers.recovery.debug("[Recovery] Resending request for orphaned draft in conversation: \(conversation.title)")
            #endif

            controller.currentConversation = conversation
            controller.messages = controller.visibleMessages(for: conversation)
                .filter { $0.id != draft.id }

            controller.applyConversationConfiguration(from: conversation)

            if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: idx)
            }

            controller.conversationRepository.delete(draft)
            controller.saveContextIfPossible("resendOrphanedDrafts.deleteBeforeRestart")

            let newDraft = Message(
                role: .assistant,
                content: "",
                thinking: nil,
                lastSequenceNumber: nil,
                usedBackgroundMode: controller.backgroundModeEnabled,
                isComplete: false
            )
            newDraft.conversation = controller.currentConversation
            controller.currentConversation?.messages.append(newDraft)
            controller.saveContextIfPossible("resendOrphanedDrafts.insertReplacementDraft")

            let preparedReply: PreparedAssistantReply
            do {
                preparedReply = try controller.prepareExistingDraft(newDraft)
            } catch SendMessagePreparationError.missingAPIKey {
                controller.errorMessage = "Please add your OpenAI API key in Settings."
                return
            } catch {
                controller.errorMessage = "Failed to restart orphaned draft."
                return
            }

            let session = ReplySession(preparedReply: preparedReply)

            controller.registerSession(session, execution: SessionExecutionState(service: controller.serviceFactory()), visible: true)
            let controller = controller
            Task { @MainActor in
                _ = await controller.applyRuntimeTransition(.beginSubmitting, to: session)
                _ = await controller.applyRuntimeTransition(.setThinking(true), to: session)
                controller.syncVisibleState(from: session)
            }
            controller.errorMessage = nil

            #if DEBUG
            Loggers.recovery.debug("[Recovery] Starting resend stream for conversation: \(conversation.title), messages count: \(controller.messages.count)")
            #endif

            controller.startStreamingRequest(for: session)
            return
        }
    }
}
