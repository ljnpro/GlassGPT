import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var roleRawValue: String
    var content: String
    var thinking: String?
    var imageData: Data?
    var createdAt: Date
    var conversation: Conversation?

    /// The OpenAI response ID (from response.created event).
    /// Used to poll for the complete response if streaming was interrupted.
    var responseId: String?

    /// Relay run identifier for relay-server-backed streaming.
    var relayRunId: String?

    /// Secret relay resume token returned by the relay server.
    var relayResumeToken: String?

    /// Highest OpenAI sequence_number acknowledged by the iOS client.
    var relayLastSequenceNumber: Int?

    /// Highest OpenAI sequence_number represented by the persisted draft state.
    var lastSequenceNumber: Int?

    /// Whether the request was started with OpenAI background mode enabled.
    var usedBackgroundMode: Bool

    /// Whether this message has been fully received.
    var isComplete: Bool

    /// JSON-encoded array of URLCitation objects from web search.
    var annotationsData: Data?

    /// JSON-encoded array of ToolCallInfo objects (web search, code interpreter).
    var toolCallsData: Data?

    /// JSON-encoded array of FileAttachment objects (user-uploaded documents).
    var fileAttachmentsData: Data?

    /// JSON-encoded array of FilePathAnnotation objects from code interpreter output.
    var filePathAnnotationsData: Data?

    init(
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
        self.roleRawValue = role.rawValue
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
        self.annotationsData = MessagePayloadStore.encodeAnnotations(annotations)
        self.toolCallsData = MessagePayloadStore.encodeToolCalls(toolCalls)
        self.fileAttachmentsData = MessagePayloadStore.encodeFileAttachments(fileAttachments)
        self.filePathAnnotationsData = MessagePayloadStore.encodeFilePathAnnotations(filePathAnnotations)
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }

    // MARK: - Annotations

    var annotations: [URLCitation] {
        get { MessagePayloadStore.annotations(from: annotationsData) }
        set { MessagePayloadStore.setAnnotations(newValue, on: self) }
    }

    // MARK: - Tool Calls

    var toolCalls: [ToolCallInfo] {
        get { MessagePayloadStore.toolCalls(from: toolCallsData) }
        set { MessagePayloadStore.setToolCalls(newValue, on: self) }
    }

    // MARK: - File Attachments

    var fileAttachments: [FileAttachment] {
        get { MessagePayloadStore.fileAttachments(from: fileAttachmentsData) }
        set { MessagePayloadStore.setFileAttachments(newValue, on: self) }
    }

    // MARK: - File Path Annotations

    var filePathAnnotations: [FilePathAnnotation] {
        get { MessagePayloadStore.filePathAnnotations(from: filePathAnnotationsData) }
        set { MessagePayloadStore.setFilePathAnnotations(newValue, on: self) }
    }

    var payloadRenderDigest: String {
        MessagePayloadStore.renderDigest(for: self)
    }
}
