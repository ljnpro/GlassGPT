import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import OpenAITransport

/// Coordinator responsible for conversation lifecycle: starting new chats, loading, restoring, and regenerating messages.
@MainActor
package final class ChatConversationCoordinator {
    unowned let state: any (
        ChatConversationSelectionAccess &
            ChatMessageListAccess &
            ChatStreamingProjectionAccess &
            ChatAttachmentStateAccess &
            ChatConfigurationSelectionAccess &
            ChatPreviewStateAccess &
            ChatReplyFeedbackAccess
    )
    unowned let services: any (
        ChatPersistenceAccess &
            ChatTransportServiceAccess &
            ChatGeneratedFileServiceAccess &
            ChatBackgroundTaskAccess
    )
    unowned var sessions: (any ChatSessionManaging)!
    unowned var recoveryMaintenance: (any ChatRecoveryMaintenanceManaging)!
    unowned var drafts: (any ChatDraftPreparing)!
    unowned var streaming: (any ChatStreamingRequestStarting)!

    /// Creates a coordinator with the given state and service surfaces.
    init(
        state: any(
            ChatConversationSelectionAccess &
                ChatMessageListAccess &
                ChatStreamingProjectionAccess &
                ChatAttachmentStateAccess &
                ChatConfigurationSelectionAccess &
                ChatPreviewStateAccess &
                ChatReplyFeedbackAccess
        ),
        services: any(
            ChatPersistenceAccess &
                ChatTransportServiceAccess &
                ChatGeneratedFileServiceAccess &
                ChatBackgroundTaskAccess
        )
    ) {
        self.state = state
        self.services = services
    }

    /// Resets the active conversation state, saving any visible session first.
    package func startNewChat() {
        if let session = sessions.currentVisibleSession {
            sessions.saveSessionNow(session)
        }

        services.cancelGeneratedFilePrefetches(services.generatedFilePrefetchRegistry.cancelAll())
        sessions.detachVisibleSessionBinding()
        state.currentConversation = nil
        state.messages = []
        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.errorMessage = nil
        state.selectedImageData = nil
        state.pendingAttachments = []
        state.isThinking = false
        state.thinkingPresentationState = nil
        state.draftMessage = nil
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.lastSequenceNumber = nil
        state.activeRequestUsesBackgroundMode = false
        state.filePreviewItem = nil
        state.sharedGeneratedFileItem = nil
        state.fileDownloadError = nil
        loadDefaultsFromSettings()
        state.syncConversationProjection()
        state.hapticService.selection(isEnabled: state.hapticsEnabled)
    }

    /// Deletes the given assistant message and re-submits a fresh request for it.
    package func regenerateMessage(_ message: Message) {
        guard !state.isStreaming else { return }
        guard message.role == .assistant else { return }
        guard !drafts.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        if let index = state.messages.firstIndex(where: { $0.id == message.id }) {
            state.messages.remove(at: index)
        }

        if let conversation = state.currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        services.conversationRepository.delete(message)
        saveContextIfPossible("regenerateMessage.deleteOriginal")

        state.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: state.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = state.currentConversation
        state.currentConversation?.messages.append(draft)
        saveContextIfPossible("regenerateMessage.insertDraft")

        let preparedReply: PreparedAssistantReply
        do {
            preparedReply = try drafts.prepareExistingDraft(draft)
        } catch SendMessagePreparationError.missingAPIKey {
            state.errorMessage = "Please add your OpenAI API key in Settings."
            return
        } catch {
            state.errorMessage = "Failed to start response session."
            return
        }

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
            sessions.syncVisibleState(from: session)
        }

        state.hapticService.impact(.medium, isEnabled: state.hapticsEnabled)
        streaming.startStreamingRequest(for: session, reconnectAttempt: 0)
    }

    /// Loads an existing conversation from persistence, replacing the current session.
    package func loadConversation(_ conversation: Conversation) {
        if let session = sessions.currentVisibleSession {
            sessions.saveSessionNow(session)
        }

        services.cancelGeneratedFilePrefetches(services.generatedFilePrefetchRegistry.cancelAll())
        sessions.detachVisibleSessionBinding()
        state.currentConversation = conversation
        state.messages = visibleMessages(for: conversation)
        state.syncConversationProjection()

        applyConversationConfiguration(from: conversation)

        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.errorMessage = nil
        state.isThinking = false
        state.thinkingPresentationState = nil
        state.draftMessage = nil
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.lastSequenceNumber = nil
        state.activeRequestUsesBackgroundMode = false
        state.pendingAttachments = []
        state.filePreviewItem = nil
        state.sharedGeneratedFileItem = nil
        state.fileDownloadError = nil

        sessions.refreshVisibleBindingForCurrentConversation()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await recoveryMaintenance.recoverIncompleteMessagesInCurrentConversation()
        }
    }

    /// Attempts to restore the most recent conversation from persistence on app launch.
    package func restoreLastConversationIfAvailable() {
        do {
            if let lastConversation = try services.conversationRepository.fetchMostRecentConversationWithMessages() {
                state.currentConversation = lastConversation
                state.messages = visibleMessages(for: lastConversation)

                applyConversationConfiguration(from: lastConversation)

                #if DEBUG
                Loggers.chat.debug("[Restore] Loaded last conversation: \(lastConversation.title) (\(state.messages.count) messages)")
                #endif
            }
        } catch {
            Loggers.persistence.error("[restoreLastConversationIfAvailable] \(error.localizedDescription)")
        }
    }

    /// Returns the current incomplete assistant draft message, if one exists.
    package func activeIncompleteAssistantDraft() -> Message? {
        if let draft = state.draftMessage, !draft.isComplete, draft.role == .assistant {
            return draft
        }

        return state.currentConversation?.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }
}
