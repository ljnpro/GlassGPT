import Foundation

@MainActor
extension ChatController {
    func recoverIncompleteMessages() async {
        await recoveryMaintenanceCoordinator.recoverIncompleteMessages()
    }

    func cleanupStaleDrafts() async {
        await recoveryMaintenanceCoordinator.cleanupStaleDrafts()
    }

    func resendOrphanedDrafts() async {
        await recoveryMaintenanceCoordinator.resendOrphanedDrafts()
    }
}
