import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData

/// SwiftData entity representing a single chat message within a ``Conversation``.
@Model
public final class Message {
    package static let roleFallbackLogger = Loggers.persistence
    /// Unique identifier for this message.
    public var id: UUID
    /// Stable server-side identifier for this message projection.
    public var serverID: String?
    /// Stable backend account identifier that owns this cached message.
    public var syncAccountID: String?
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
    /// Timestamp when the server marked this message complete, if available.
    public var completedAt: Date?
    /// The conversation this message belongs to.
    public var conversation: Conversation?
    /// Stable server-side run identifier for the run that produced this message.
    public var serverRunID: String?
    /// Stable server-side sync cursor for the event that last updated this message.
    public var serverCursor: String?
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
    /// Encoded Agent-process trace payload.
    public var agentTraceData: Data?

    /// Creates a new message with the given parameters.
    public init(
        id: UUID = UUID(),
        serverID: String? = nil,
        syncAccountID: String? = nil,
        role: MessageRole = .user,
        content: String = "",
        thinking: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        conversation: Conversation? = nil,
        serverRunID: String? = nil,
        serverCursor: String? = nil,
        isComplete: Bool = true,
        annotations: [URLCitation]? = nil,
        toolCalls: [ToolCallInfo]? = nil,
        fileAttachments: [FileAttachment]? = nil,
        filePathAnnotations: [FilePathAnnotation]? = nil,
        agentTrace: AgentTurnTrace? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.syncAccountID = syncAccountID
        roleRawValue = role.rawValue
        self.content = content
        self.thinking = thinking
        self.imageData = imageData
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.conversation = conversation
        self.serverRunID = serverRunID
        self.serverCursor = serverCursor
        self.isComplete = isComplete
        annotationsData = MessagePayloadStore.encodeAnnotations(annotations)
        toolCallsData = MessagePayloadStore.encodeToolCalls(toolCalls)
        fileAttachmentsData = MessagePayloadStore.encodeFileAttachments(fileAttachments)
        filePathAnnotationsData = MessagePayloadStore.encodeFilePathAnnotations(filePathAnnotations)
        agentTraceData = PersistencePayloadCoder.encode(agentTrace, owner: "Message")
    }

    /// Typed accessor for the message role, derived from ``roleRawValue``.
    public var role: MessageRole {
        get { Self.resolvedRole(from: roleRawValue) }
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

    /// Decoded Agent-mode process trace, if this assistant reply came from Agent mode.
    public var agentTrace: AgentTurnTrace? {
        get { PersistencePayloadCoder.decode(AgentTurnTrace.self, from: agentTraceData, owner: "Message") }
        set { agentTraceData = PersistencePayloadCoder.encode(newValue, owner: "Message") }
    }

    /// SHA-256 hex digest of all payload blobs, used for change detection.
    public var payloadRenderDigest: String {
        MessagePayloadStore.renderDigest(for: self)
    }

    package static func resolvedRole(
        from rawValue: String,
        onInvalid: ((String) -> Void)? = nil,
        logFailure: Bool = true
    ) -> MessageRole {
        guard let role = MessageRole(rawValue: rawValue) else {
            onInvalid?(rawValue)
            if logFailure {
                roleFallbackLogger.error("Unknown message role raw value: \(rawValue)")
            }
            return .user
        }

        return role
    }
}
