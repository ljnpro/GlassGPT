import ChatDomain
import Foundation
import SwiftData

/// SwiftData entity representing a single chat message within a ``Conversation``.
@Model
public final class Message {
    /// Unique identifier for this message.
    public var id: UUID
    /// Raw value of the ``MessageRole`` (e.g. "user", "assistant").
    public var roleRawValue: String
    /// The text body of the message.
    public var content: String
    /// Optional reasoning/thinking content produced by the model.
    public var thinking: String?
    /// Optional image data attached to the message.
    public var imageData: Data?
    /// Timestamp when the message was created.
    public var createdAt: Date
    /// The conversation this message belongs to.
    public var conversation: Conversation?
    /// OpenAI response identifier, used for recovery and resumption.
    public var responseId: String?
    /// Relay run identifier for background-mode sessions.
    public var relayRunId: String?
    /// Token used to resume a relay-based background session.
    public var relayResumeToken: String?
    /// Last SSE sequence number received via relay transport.
    public var relayLastSequenceNumber: Int?
    /// Last SSE sequence number received during standard streaming.
    public var lastSequenceNumber: Int?
    /// Whether this message was generated using background mode.
    public var usedBackgroundMode: Bool
    /// Whether the assistant has finished generating this message.
    public var isComplete: Bool
    /// Encoded URL citation payload.
    public var annotationsData: Data?
    /// Encoded tool call metadata payload.
    public var toolCallsData: Data?
    /// Encoded file attachment payload.
    public var fileAttachmentsData: Data?
    /// Encoded file-path annotation payload.
    public var filePathAnnotationsData: Data?

    /// Creates a new message with the given parameters.
    public init(
        id: UUID = UUID(),
        role: MessageRole = .user,
        content: String = "",
        thinking: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now,
        conversation: Conversation? = nil,
        responseId: String? = nil,
        relayRunId: String? = nil,
        relayResumeToken: String? = nil,
        relayLastSequenceNumber: Int? = nil,
        lastSequenceNumber: Int? = nil,
        usedBackgroundMode: Bool = false,
        isComplete: Bool = true,
        annotations: [URLCitation]? = nil,
        toolCalls: [ToolCallInfo]? = nil,
        fileAttachments: [FileAttachment]? = nil,
        filePathAnnotations: [FilePathAnnotation]? = nil
    ) {
        self.id = id
        roleRawValue = role.rawValue
        self.content = content
        self.thinking = thinking
        self.imageData = imageData
        self.createdAt = createdAt
        self.conversation = conversation
        self.responseId = responseId
        self.relayRunId = relayRunId
        self.relayResumeToken = relayResumeToken
        self.relayLastSequenceNumber = relayLastSequenceNumber
        self.lastSequenceNumber = lastSequenceNumber
        self.usedBackgroundMode = usedBackgroundMode
        self.isComplete = isComplete
        annotationsData = MessagePayloadStore.encodeAnnotations(annotations)
        toolCallsData = MessagePayloadStore.encodeToolCalls(toolCalls)
        fileAttachmentsData = MessagePayloadStore.encodeFileAttachments(fileAttachments)
        filePathAnnotationsData = MessagePayloadStore.encodeFilePathAnnotations(filePathAnnotations)
    }

    /// Typed accessor for the message role, derived from ``roleRawValue``.
    public var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }

    /// Decoded URL citations. Setting this value re-encodes and stores the data blob.
    public var annotations: [URLCitation] {
        get { MessagePayloadStore.annotations(from: annotationsData) }
        set { MessagePayloadStore.setAnnotations(newValue, on: self) }
    }

    /// Decoded tool call metadata. Setting this value re-encodes and stores the data blob.
    public var toolCalls: [ToolCallInfo] {
        get { MessagePayloadStore.toolCalls(from: toolCallsData) }
        set { MessagePayloadStore.setToolCalls(newValue, on: self) }
    }

    /// Decoded file attachments. Setting this value re-encodes and stores the data blob.
    public var fileAttachments: [FileAttachment] {
        get { MessagePayloadStore.fileAttachments(from: fileAttachmentsData) }
        set { MessagePayloadStore.setFileAttachments(newValue, on: self) }
    }

    /// Decoded file-path annotations. Setting this value re-encodes and stores the data blob.
    public var filePathAnnotations: [FilePathAnnotation] {
        get { MessagePayloadStore.filePathAnnotations(from: filePathAnnotationsData) }
        set { MessagePayloadStore.setFilePathAnnotations(newValue, on: self) }
    }

    /// SHA-256 hex digest of all payload blobs, used for change detection.
    public var payloadRenderDigest: String {
        MessagePayloadStore.renderDigest(for: self)
    }
}
