import ChatDomain
import Foundation

/// Errors that can occur while preparing to send a message.
public enum SendMessagePreparationError: Error, Equatable, Sendable {
    /// A streaming session is already active for this conversation.
    case alreadyStreaming
    /// The user message content is empty.
    case emptyInput
    /// No API key is configured.
    case missingAPIKey
    /// The user message could not be saved to persistence.
    case failedToPersistUserMessage
    /// The assistant draft message could not be created.
    case failedToCreateDraft
}

/// Contains all data needed to initiate an assistant reply streaming session.
public struct PreparedAssistantReply: Sendable, Equatable {
    /// The runtime identifier for this reply session, assigned when streaming begins.
    public var assistantReplyID: AssistantReplyID?
    /// The API key to authenticate the request.
    public let apiKey: String
    /// The unique identifier of the user's message that prompted this reply.
    public let userMessageID: UUID
    /// The unique identifier of the draft message that will hold the assistant's response.
    public let draftMessageID: UUID
    /// The conversation this reply belongs to.
    public let conversationID: UUID
    /// The full message history to send with the completion request.
    public let requestMessages: [ChatRequestMessage]
    /// The model to use for this completion.
    public let requestModel: ModelType
    /// The reasoning effort level for this completion.
    public let requestEffort: ReasoningEffort
    /// Whether this request should continue processing in the background.
    public let requestUsesBackgroundMode: Bool
    /// The service tier for this request.
    public let requestServiceTier: ServiceTier
    /// File attachments that need to be uploaded before streaming begins.
    public let attachmentsToUpload: [FileAttachment]

    /// Creates a new prepared assistant reply.
    /// - Parameters:
    ///   - assistantReplyID: The runtime reply identifier.
    ///   - apiKey: The API authentication key.
    ///   - userMessageID: The user message identifier.
    ///   - draftMessageID: The draft message identifier.
    ///   - conversationID: The conversation identifier.
    ///   - requestMessages: The message history for the request.
    ///   - requestModel: The model to use.
    ///   - requestEffort: The reasoning effort level.
    ///   - requestUsesBackgroundMode: Whether background mode is enabled.
    ///   - requestServiceTier: The service tier.
    ///   - attachmentsToUpload: Files to upload before streaming.
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
