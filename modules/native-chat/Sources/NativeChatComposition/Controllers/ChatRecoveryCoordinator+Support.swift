import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    func syncCompletionState(for message: Message) {
        controller.fileInteractionCoordinator.prefetchGeneratedFilesIfNeeded(for: message)
    }
}
