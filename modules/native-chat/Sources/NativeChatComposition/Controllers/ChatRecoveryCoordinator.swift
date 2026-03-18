import Foundation

@MainActor
final class ChatRecoveryCoordinator {
    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }
}
