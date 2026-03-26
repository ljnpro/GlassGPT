import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation

@MainActor
final class AgentConversationCoordinator {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func startNewConversation() {
        state.sessionRegistry.bindVisibleConversation(nil)
        state.currentConversation = nil
        state.messages = []
        state.selectedImageData = nil
        state.pendingAttachments = []
        loadDefaultsFromSettings()
        clearVisibleRunState(clearDraft: true)
        state.errorMessage = nil
        state.hapticService.selection(isEnabled: state.hapticsEnabled)
    }

    func restoreLastConversationIfAvailable() {
        do {
            guard let conversation = try state.conversationRepository.fetchMostRecentConversationWithMessages(mode: .agent) else {
                return
            }

            state.sessionRegistry.bindVisibleConversation(nil)
            state.currentConversation = conversation
            state.messages = visibleMessages(for: conversation)
            state.selectedImageData = nil
            state.pendingAttachments = []
            applyConversationConfiguration(resolvedConfiguration(for: conversation), persist: false)
            state.errorMessage = nil
            restoreDraftIfNeeded(
                from: conversation,
                autoResume: false,
                showRetryBannerWhenDormant: false
            )
        } catch {
            Loggers.persistence.error("[AgentConversationCoordinator.restoreLastConversationIfAvailable] \(error.localizedDescription)")
        }
    }

    func loadConversation(_ conversation: Conversation) {
        state.sessionRegistry.bindVisibleConversation(nil)
        state.currentConversation = conversation
        state.messages = visibleMessages(for: conversation)
        state.selectedImageData = nil
        state.pendingAttachments = []
        applyConversationConfiguration(resolvedConfiguration(for: conversation), persist: false)
        state.errorMessage = nil
        restoreDraftIfNeeded(
            from: conversation,
            autoResume: true,
            showRetryBannerWhenDormant: true
        )
    }

    func saveContext(_ logContext: String) -> Bool {
        do {
            try state.conversationRepository.save()
            return true
        } catch {
            Loggers.persistence.error("[AgentConversationCoordinator.\(logContext)] \(error.localizedDescription)")
            state.errorMessage = "Failed to save the Agent conversation."
            return false
        }
    }

    func visibleMessages(for conversation: Conversation) -> [Message] {
        conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
    }
}
