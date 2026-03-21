import ChatDomain
import Foundation

/// A position marker for resuming an interrupted streaming session.
public struct StreamCursor: Equatable, Sendable {
    /// The API response identifier to resume.
    public let responseID: String
    /// The last successfully received event sequence number, if any.
    public let lastSequenceNumber: Int?
    /// The transport route used for the original stream.
    public let route: OpenAITransportRoute

    /// Creates a new stream cursor.
    /// - Parameters:
    ///   - responseID: The API response identifier.
    ///   - lastSequenceNumber: The last received sequence number.
    ///   - route: The transport route used.
    public init(
        responseID: String,
        lastSequenceNumber: Int?,
        route: OpenAITransportRoute
    ) {
        self.responseID = responseID
        self.lastSequenceNumber = lastSequenceNumber
        self.route = route
    }
}

/// Accumulates content fragments received during a streaming assistant reply.
public struct ReplyBuffer: Equatable, Sendable {
    /// The accumulated text content of the reply.
    public var text: String
    /// The accumulated reasoning/thinking content, if the model supports it.
    public var thinking: String
    /// Tool calls invoked by the assistant during this reply.
    public var toolCalls: [ToolCallInfo]
    /// URL citations referenced in the reply text.
    public var citations: [URLCitation]
    /// File path annotations referencing sandbox-generated files.
    public var filePathAnnotations: [FilePathAnnotation]
    /// File attachments included with the reply.
    public var attachments: [FileAttachment]

    /// Creates a new empty reply buffer.
    /// - Parameters:
    ///   - text: Initial text content. Defaults to empty.
    ///   - thinking: Initial thinking content. Defaults to empty.
    ///   - toolCalls: Initial tool calls. Defaults to empty.
    ///   - citations: Initial citations. Defaults to empty.
    ///   - filePathAnnotations: Initial file path annotations. Defaults to empty.
    ///   - attachments: Initial attachments. Defaults to empty.
    public init(
        text: String = "",
        thinking: String = "",
        toolCalls: [ToolCallInfo] = [],
        citations: [URLCitation] = [],
        filePathAnnotations: [FilePathAnnotation] = [],
        attachments: [FileAttachment] = []
    ) {
        self.text = text
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.citations = citations
        self.filePathAnnotations = filePathAnnotations
        self.attachments = attachments
    }
}

/// Information needed to recover a detached background reply session.
public struct DetachedRecoveryTicket: Equatable, Sendable {
    /// The runtime identifier of the detached reply.
    public let assistantReplyID: AssistantReplyID
    /// The persisted message identifier.
    public let messageID: UUID
    /// The owning conversation identifier.
    public let conversationID: UUID
    /// The API response identifier for the detached session.
    public let responseID: String
    /// The last received sequence number before detachment.
    public let lastSequenceNumber: Int?
    /// Whether the original request used background mode.
    public let usedBackgroundMode: Bool
    /// The transport route used for the original request.
    public let route: OpenAITransportRoute

    /// Creates a new detached recovery ticket.
    /// - Parameters:
    ///   - assistantReplyID: The runtime reply identifier.
    ///   - messageID: The persisted message identifier.
    ///   - conversationID: The conversation identifier.
    ///   - responseID: The API response identifier.
    ///   - lastSequenceNumber: The last received sequence number.
    ///   - usedBackgroundMode: Whether background mode was used.
    ///   - route: The transport route.
    public init(
        assistantReplyID: AssistantReplyID,
        messageID: UUID,
        conversationID: UUID,
        responseID: String,
        lastSequenceNumber: Int?,
        usedBackgroundMode: Bool,
        route: OpenAITransportRoute
    ) {
        self.assistantReplyID = assistantReplyID
        self.messageID = messageID
        self.conversationID = conversationID
        self.responseID = responseID
        self.lastSequenceNumber = lastSequenceNumber
        self.usedBackgroundMode = usedBackgroundMode
        self.route = route
    }
}
