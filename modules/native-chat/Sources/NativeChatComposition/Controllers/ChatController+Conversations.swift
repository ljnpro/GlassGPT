import ChatPersistenceSwiftData
import Foundation

@MainActor
extension ChatController {
    package func startNewChat() {
        conversationCoordinator.startNewChat()
    }

    func regenerateMessage(_ message: Message) {
        conversationCoordinator.regenerateMessage(message)
    }

    package func loadConversation(_ conversation: ChatPersistenceSwiftData.Conversation) {
        conversationCoordinator.loadConversation(conversation)
    }

    func restoreLastConversationIfAvailable() {
        conversationCoordinator.restoreLastConversationIfAvailable()
    }

    @discardableResult
    func saveContext(
        reportingUserError userError: String? = nil,
        logContext: String
    ) -> Bool {
        conversationCoordinator.saveContext(reportingUserError: userError, logContext: logContext)
    }

    func saveContextIfPossible(_ logContext: String) {
        conversationCoordinator.saveContextIfPossible(logContext)
    }

    func loadDefaultsFromSettings() {
        conversationCoordinator.loadDefaultsFromSettings()
    }

    func applyConversationConfiguration(from conversation: Conversation) {
        conversationCoordinator.applyConversationConfiguration(from: conversation)
    }

    func activeIncompleteAssistantDraft() -> Message? {
        conversationCoordinator.activeIncompleteAssistantDraft()
    }

    func visibleMessages(for conversation: Conversation) -> [Message] {
        conversationCoordinator.visibleMessages(for: conversation)
    }

    func shouldHideMessage(_ message: Message) -> Bool {
        conversationCoordinator.shouldHideMessage(message)
    }

    func syncConversationConfiguration() {
        conversationCoordinator.syncConversationConfiguration()
    }

    func upsertMessage(_ message: Message) {
        conversationCoordinator.upsertMessage(message)
    }
}
