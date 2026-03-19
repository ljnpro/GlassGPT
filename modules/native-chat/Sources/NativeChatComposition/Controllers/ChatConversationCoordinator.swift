import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
/// Coordinator responsible for conversation lifecycle: starting new chats, loading, restoring, and regenerating messages.
package final class ChatConversationCoordinator {
    unowned let controller: ChatController

    /// Creates a coordinator bound to the given chat controller.
    package init(controller: ChatController) {
        self.controller = controller
    }

    /// Resets the controller to a blank conversation, saving any active session first.
    package func startNewChat() {
        if let session = controller.currentVisibleSession {
            controller.sessionCoordinator.saveSessionNow(session)
        }

        controller.cancelGeneratedFilePrefetches(controller.generatedFilePrefetchRegistry.cancelAll())
        controller.sessionCoordinator.detachVisibleSessionBinding()
        controller.currentConversation = nil
        controller.messages = []
        controller.currentStreamingText = ""
        controller.currentThinkingText = ""
        controller.errorMessage = nil
        controller.selectedImageData = nil
        controller.pendingAttachments = []
        controller.isThinking = false
        controller.draftMessage = nil
        controller.activeToolCalls = []
        controller.liveCitations = []
        controller.liveFilePathAnnotations = []
        controller.lastSequenceNumber = nil
        controller.activeRequestUsesBackgroundMode = false
        controller.filePreviewItem = nil
        controller.sharedGeneratedFileItem = nil
        controller.fileDownloadError = nil
        loadDefaultsFromSettings()
        controller.syncConversationProjection()
        controller.hapticService.selection(isEnabled: controller.hapticsEnabled)
    }

    /// Deletes the given assistant message and re-submits a fresh request for it.
    package func regenerateMessage(_ message: Message) {
        guard !controller.isStreaming else { return }
        guard message.role == .assistant else { return }
        guard !controller.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            controller.errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        if let index = controller.messages.firstIndex(where: { $0.id == message.id }) {
            controller.messages.remove(at: index)
        }

        if let conversation = controller.currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        controller.conversationRepository.delete(message)
        saveContextIfPossible("regenerateMessage.deleteOriginal")

        controller.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: controller.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = controller.currentConversation
        controller.currentConversation?.messages.append(draft)
        saveContextIfPossible("regenerateMessage.insertDraft")

        let preparedReply: PreparedAssistantReply
        do {
            preparedReply = try controller.prepareExistingDraft(draft)
        } catch SendMessagePreparationError.missingAPIKey {
            controller.errorMessage = "Please add your OpenAI API key in Settings."
            return
        } catch {
            controller.errorMessage = "Failed to start response session."
            return
        }

        let session = ReplySession(preparedReply: preparedReply)
        controller.sessionCoordinator.registerSession(
            session,
            execution: SessionExecutionState(service: controller.serviceFactory()),
            visible: true
        )
        let controller = controller
        Task { @MainActor in
            _ = await controller.sessionCoordinator.applyRuntimeTransition(.beginSubmitting, to: session)
            controller.sessionCoordinator.syncVisibleState(from: session)
        }

        controller.hapticService.impact(.medium, isEnabled: controller.hapticsEnabled)
        controller.startStreamingRequest(for: session)
    }

    /// Loads an existing conversation from persistence, replacing the current session.
    package func loadConversation(_ conversation: Conversation) {
        if let session = controller.currentVisibleSession {
            controller.sessionCoordinator.saveSessionNow(session)
        }

        controller.cancelGeneratedFilePrefetches(controller.generatedFilePrefetchRegistry.cancelAll())
        controller.sessionCoordinator.detachVisibleSessionBinding()
        controller.currentConversation = conversation
        controller.messages = visibleMessages(for: conversation)
        controller.syncConversationProjection()

        applyConversationConfiguration(from: conversation)

        controller.currentStreamingText = ""
        controller.currentThinkingText = ""
        controller.errorMessage = nil
        controller.isThinking = false
        controller.draftMessage = nil
        controller.activeToolCalls = []
        controller.liveCitations = []
        controller.liveFilePathAnnotations = []
        controller.lastSequenceNumber = nil
        controller.activeRequestUsesBackgroundMode = false
        controller.pendingAttachments = []
        controller.filePreviewItem = nil
        controller.sharedGeneratedFileItem = nil
        controller.fileDownloadError = nil

        controller.sessionCoordinator.refreshVisibleBindingForCurrentConversation()

        let controller = controller
        Task { @MainActor in
            await controller.recoverIncompleteMessagesInCurrentConversation()
        }
    }

    /// Attempts to restore the most recent conversation from persistence on app launch.
    package func restoreLastConversationIfAvailable() {
        do {
            if let lastConversation = try controller.conversationRepository.fetchMostRecentConversationWithMessages() {
                controller.currentConversation = lastConversation
                controller.messages = visibleMessages(for: lastConversation)

                applyConversationConfiguration(from: lastConversation)

                #if DEBUG
                Loggers.chat.debug("[Restore] Loaded last conversation: \(lastConversation.title) (\(controller.messages.count) messages)")
                #endif
            }
        } catch {
            Loggers.persistence.error("[restoreLastConversationIfAvailable] \(error.localizedDescription)")
        }
    }

    /// Returns the current incomplete assistant draft message, if one exists.
    package func activeIncompleteAssistantDraft() -> Message? {
        if let draft = controller.draftMessage, !draft.isComplete, draft.role == .assistant {
            return draft
        }

        return controller.currentConversation?.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }
}
