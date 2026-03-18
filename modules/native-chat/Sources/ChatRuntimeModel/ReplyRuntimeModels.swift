import ChatDomain
import Foundation

public struct StreamCursor: Equatable, Sendable {
    public let responseID: String
    public let lastSequenceNumber: Int?
    public let route: OpenAITransportRoute

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

public struct ReplyBuffer: Equatable, Sendable {
    public var text: String
    public var thinking: String
    public var toolCalls: [ToolCallInfo]
    public var citations: [URLCitation]
    public var filePathAnnotations: [FilePathAnnotation]
    public var attachments: [FileAttachment]

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

public struct DetachedRecoveryTicket: Equatable, Sendable {
    public let assistantReplyID: AssistantReplyID
    public let messageID: UUID
    public let conversationID: UUID
    public let responseID: String
    public let lastSequenceNumber: Int?
    public let usedBackgroundMode: Bool
    public let route: OpenAITransportRoute

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

public enum ReplyLifecycle: Equatable, Sendable {
    case idle
    case preparingInput
    case uploadingAttachments
    case streaming(StreamCursor)
    case detached(DetachedRecoveryTicket)
    case recoveringStatus(DetachedRecoveryTicket)
    case recoveringStream(StreamCursor)
    case recoveringPoll(DetachedRecoveryTicket)
    case finalizing
    case completed
    case failed(String?)
}

public struct ReplyRuntimeState: Equatable, Sendable {
    public let assistantReplyID: AssistantReplyID
    public let messageID: UUID
    public let conversationID: UUID
    public var lifecycle: ReplyLifecycle
    public var buffer: ReplyBuffer
    public var cursor: StreamCursor?

    public init(
        assistantReplyID: AssistantReplyID,
        messageID: UUID,
        conversationID: UUID,
        lifecycle: ReplyLifecycle = .idle,
        buffer: ReplyBuffer = .init(),
        cursor: StreamCursor? = nil
    ) {
        self.assistantReplyID = assistantReplyID
        self.messageID = messageID
        self.conversationID = conversationID
        self.lifecycle = lifecycle
        self.buffer = buffer
        self.cursor = cursor
    }
}
