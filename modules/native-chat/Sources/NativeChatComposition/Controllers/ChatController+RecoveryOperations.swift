import ChatPersistenceSwiftData
import Foundation

@MainActor
extension ChatController {
    func recoverIncompleteMessagesInCurrentConversation() async {
        await recoveryMaintenanceCoordinator.recoverIncompleteMessagesInCurrentConversation()
    }

    func recoverSingleMessage(message: Message, responseId: String, visible: Bool) {
        recoveryMaintenanceCoordinator.recoverSingleMessage(message: message, responseId: responseId, visible: visible)
    }
}
