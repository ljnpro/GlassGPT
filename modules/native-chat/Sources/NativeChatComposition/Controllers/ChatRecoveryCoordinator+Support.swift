import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    func syncCompletionState(for message: Message) {
        files.prefetchGeneratedFilesIfNeeded(for: message)
    }
}
