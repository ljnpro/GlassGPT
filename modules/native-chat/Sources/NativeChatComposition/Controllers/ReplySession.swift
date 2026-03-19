import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation
import OpenAITransport

@MainActor
final class ReplySession {
    let assistantReplyID: AssistantReplyID
    let messageID: UUID
    let conversationID: UUID
    let request: ResponseRequestContext

    var lastDraftSaveTime: Date = .distantPast

    init(
        assistantReplyID: AssistantReplyID? = nil,
        message: Message,
        conversationID: UUID,
        request: ResponseRequestContext
    ) {
        self.assistantReplyID = assistantReplyID ?? AssistantReplyID(rawValue: message.id)
        messageID = message.id
        self.conversationID = conversationID
        self.request = request
    }

    convenience init(
        preparedReply: PreparedAssistantReply
    ) {
        let message = Message(
            id: preparedReply.draftMessageID,
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: preparedReply.requestUsesBackgroundMode,
            isComplete: false
        )
        self.init(
            assistantReplyID: preparedReply.assistantReplyID,
            message: message,
            conversationID: preparedReply.conversationID,
            request: ResponseRequestContext(
                apiKey: preparedReply.apiKey,
                messages: preparedReply.requestMessages,
                model: preparedReply.requestModel,
                effort: preparedReply.requestEffort,
                usesBackgroundMode: preparedReply.requestUsesBackgroundMode,
                serviceTier: preparedReply.requestServiceTier
            )
        )
    }
}
