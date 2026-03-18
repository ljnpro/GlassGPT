import ChatDomain
import Foundation
import SwiftData

@Model
public final class Message {
    public var id: UUID
    public var roleRawValue: String
    public var content: String
    public var thinking: String?
    public var imageData: Data?
    public var createdAt: Date
    public var conversation: Conversation?
    public var responseId: String?
    public var relayRunId: String?
    public var relayResumeToken: String?
    public var relayLastSequenceNumber: Int?
    public var lastSequenceNumber: Int?
    public var usedBackgroundMode: Bool
    public var isComplete: Bool
    public var annotationsData: Data?
    public var toolCallsData: Data?
    public var fileAttachmentsData: Data?
    public var filePathAnnotationsData: Data?

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

    public var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }

    public var annotations: [URLCitation] {
        get { MessagePayloadStore.annotations(from: annotationsData) }
        set { MessagePayloadStore.setAnnotations(newValue, on: self) }
    }

    public var toolCalls: [ToolCallInfo] {
        get { MessagePayloadStore.toolCalls(from: toolCallsData) }
        set { MessagePayloadStore.setToolCalls(newValue, on: self) }
    }

    public var fileAttachments: [FileAttachment] {
        get { MessagePayloadStore.fileAttachments(from: fileAttachmentsData) }
        set { MessagePayloadStore.setFileAttachments(newValue, on: self) }
    }

    public var filePathAnnotations: [FilePathAnnotation] {
        get { MessagePayloadStore.filePathAnnotations(from: filePathAnnotationsData) }
        set { MessagePayloadStore.setFilePathAnnotations(newValue, on: self) }
    }

    public var payloadRenderDigest: String {
        MessagePayloadStore.renderDigest(for: self)
    }
}
