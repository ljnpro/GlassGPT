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

    /// Loads an existing conversation from persistence, replacing the current session.
    package func loadConversation(_ conversation: Conversation) {
        guard conversation.mode == .chat else {
            #if DEBUG
            Loggers.chat.debug("[Load] Refused to load non-chat conversation into ChatCoordinator")
            #endif
            return
        }

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
            if let lastConversation = try services.conversationRepository.fetchMostRecentConversationWithMessages(
                mode: .chat
            ) {
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
