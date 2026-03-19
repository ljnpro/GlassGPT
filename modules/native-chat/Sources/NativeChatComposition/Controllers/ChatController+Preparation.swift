import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatController {
    /// Prepares a new assistant reply by delegating to the send coordinator.
    package func prepareSendMessage(text rawText: String) throws(SendMessagePreparationError) -> PreparedAssistantReply {
        try sendCoordinator.prepareSendMessage(text: rawText)
    }

    /// Persists uploaded attachment metadata on the user message with the given ID.
    package func persistUploadedAttachments(_ attachments: [ChatDomain.FileAttachment], onUserMessageID messageID: UUID) {
        sendCoordinator.persistUploadedAttachments(attachments, onUserMessageID: messageID)
    }

    func prepareExistingDraft(_ draft: Message) throws(SendMessagePreparationError) -> PreparedAssistantReply {
        try sendCoordinator.prepareExistingDraft(draft)
    }
}
