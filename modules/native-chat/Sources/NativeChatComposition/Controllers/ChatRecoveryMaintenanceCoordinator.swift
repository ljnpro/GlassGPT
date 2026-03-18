import Foundation

@MainActor
final class ChatRecoveryMaintenanceCoordinator {
    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }
}
