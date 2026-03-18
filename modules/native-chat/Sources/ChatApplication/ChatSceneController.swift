import ChatDomain
import ChatRuntimePorts
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation

@MainActor
public final class ChatSceneController {
    private let registry: RuntimeRegistryActor
    private let preparationPort: any SendMessagePreparationPort

    public init(
        registry: RuntimeRegistryActor,
        preparationPort: any SendMessagePreparationPort
    ) {
        self.registry = registry
        self.preparationPort = preparationPort
    }

    @discardableResult
    public func startReply(
        messageID: UUID,
        conversationID: UUID
    ) async -> AssistantReplyID {
        await registry.startSession(messageID: messageID, conversationID: conversationID)
    }

    public func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply {
        var prepared = try preparationPort.prepareSendMessage(text: rawText)
        let replyID = AssistantReplyID(rawValue: prepared.draftMessageID)
        Task {
            await registry.startSession(
                replyID: replyID,
                messageID: prepared.draftMessageID,
                conversationID: prepared.conversationID
            )
        }
        prepared.assistantReplyID = replyID
        return prepared
    }

    public func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment] {
        await preparationPort.uploadAttachments(attachments)
    }

    public func persistUploadedAttachments(_ attachments: [FileAttachment], onUserMessageID messageID: UUID) {
        preparationPort.persistUploadedAttachments(attachments, onUserMessageID: messageID)
    }
}
