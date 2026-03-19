import ChatPersistenceSwiftData
import Foundation

@MainActor
extension ChatController {
    func findMessage(byId id: UUID) -> Message? {
        conversationCoordinator.findMessage(byId: id)
    }
}
