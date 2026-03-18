import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
final class ChatSessionCoordinator {
    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }
}
