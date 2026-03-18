import Foundation

@MainActor
final class ChatRecoveryCoordinator {
    unowned let controller: ChatController
    let resultApplier: ChatRecoveryResultApplier

    init(controller: ChatController) {
        self.controller = controller
        self.resultApplier = ChatRecoveryResultApplier(controller: controller)
    }
}
