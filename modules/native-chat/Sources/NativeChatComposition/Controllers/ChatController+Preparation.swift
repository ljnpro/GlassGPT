import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatController {
    package func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply {
        try sendCoordinator.prepareSendMessage(text: rawText)
    }

    package func persistUploadedAttachments(_ attachments: [ChatDomain.FileAttachment], onUserMessageID messageID: UUID) {
        sendCoordinator.persistUploadedAttachments(attachments, onUserMessageID: messageID)
    }

    func prepareExistingDraft(_ draft: Message) throws -> PreparedAssistantReply {
        try sendCoordinator.prepareExistingDraft(draft)
    }
}
