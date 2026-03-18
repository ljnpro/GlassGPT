import ChatDomain
import ChatRuntimeModel
import Foundation

@MainActor
public protocol SendMessagePreparationPort: AnyObject {
    func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply
    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment]
    func persistUploadedAttachments(_ attachments: [FileAttachment], onUserMessageID messageID: UUID)
}
