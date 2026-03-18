import ChatDomain
import Foundation

public enum SendMessagePreparationError: Error, Equatable, Sendable {
    case alreadyStreaming
    case emptyInput
    case missingAPIKey
    case failedToPersistUserMessage
    case failedToCreateDraft
}

public struct PreparedAssistantReply: Sendable, Equatable {
    public var assistantReplyID: AssistantReplyID?
    public let apiKey: String
    public let userMessageID: UUID
    public let draftMessageID: UUID
    public let conversationID: UUID
    public let requestMessages: [ChatRequestMessage]
    public let requestModel: ModelType
    public let requestEffort: ReasoningEffort
    public let requestUsesBackgroundMode: Bool
    public let requestServiceTier: ServiceTier
    public let attachmentsToUpload: [FileAttachment]

    public init(
        assistantReplyID: AssistantReplyID? = nil,
        apiKey: String,
        userMessageID: UUID,
        draftMessageID: UUID,
        conversationID: UUID,
        requestMessages: [ChatRequestMessage],
        requestModel: ModelType,
        requestEffort: ReasoningEffort,
        requestUsesBackgroundMode: Bool,
        requestServiceTier: ServiceTier,
        attachmentsToUpload: [FileAttachment]
    ) {
        self.assistantReplyID = assistantReplyID
        self.apiKey = apiKey
        self.userMessageID = userMessageID
        self.draftMessageID = draftMessageID
        self.conversationID = conversationID
        self.requestMessages = requestMessages
        self.requestModel = requestModel
        self.requestEffort = requestEffort
        self.requestUsesBackgroundMode = requestUsesBackgroundMode
        self.requestServiceTier = requestServiceTier
        self.attachmentsToUpload = attachmentsToUpload
    }
}
