import ChatPersistenceSwiftData
import Foundation

@MainActor
extension ChatController {
    func generateTitlesForUntitledConversations() async {
        await lifecycleCoordinator.generateTitlesForUntitledConversations()
    }

    func generateTitleIfNeeded(for conversation: Conversation) async {
        await lifecycleCoordinator.generateTitleIfNeeded(for: conversation)
    }

    func generateTitle() async {
        await lifecycleCoordinator.generateTitle()
    }
}
