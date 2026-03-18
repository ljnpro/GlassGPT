import ChatPersistenceSwiftData
import Foundation

@MainActor
extension ChatController {
    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        recoveryCoordinator.recoverResponse(
            messageId: messageId,
            responseId: responseId,
            preferStreamingResume: preferStreamingResume,
            visible: visible
        )
    }
}
