import ChatDomain
import Foundation

public struct APIMessage: Sendable {
    public let role: MessageRole
    public let content: String
    public let imageData: Data?
    public let fileAttachments: [FileAttachment]

    public init(
        role: MessageRole,
        content: String,
        imageData: Data? = nil,
        fileAttachments: [FileAttachment] = []
    ) {
        self.role = role
        self.content = content
        self.imageData = imageData
        self.fileAttachments = fileAttachments
    }
}

public enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingStarted
    case thinkingFinished
    case responseCreated(String)
    case sequenceUpdate(Int)
    case completed(String, String?, [FilePathAnnotation]?)
    case incomplete(String, String?, [FilePathAnnotation]?, String?)
    case connectionLost
    case error(OpenAIServiceError)

    case webSearchStarted(String)
    case webSearchSearching(String)
    case webSearchCompleted(String)
    case codeInterpreterStarted(String)
    case codeInterpreterInterpreting(String)
    case codeInterpreterCodeDelta(String, String)
    case codeInterpreterCodeDone(String, String)
    case codeInterpreterCompleted(String)
    case fileSearchStarted(String)
    case fileSearchSearching(String)
    case fileSearchCompleted(String)

    case annotationAdded(URLCitation)
    case filePathAnnotationAdded(FilePathAnnotation)
}

public struct OpenAIResponseFetchResult: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case queued
        case inProgress = "in_progress"
        case completed
        case failed
        case incomplete
        case unknown
    }

    public let status: Status
    public let text: String
    public let thinking: String?
    public let annotations: [URLCitation]
    public let toolCalls: [ToolCallInfo]
    public let filePathAnnotations: [FilePathAnnotation]
    public let errorMessage: String?

    public init(
        status: Status,
        text: String,
        thinking: String?,
        annotations: [URLCitation],
        toolCalls: [ToolCallInfo],
        filePathAnnotations: [FilePathAnnotation],
        errorMessage: String?
    ) {
        self.status = status
        self.text = text
        self.thinking = thinking
        self.annotations = annotations
        self.toolCalls = toolCalls
        self.filePathAnnotations = filePathAnnotations
        self.errorMessage = errorMessage
    }
}
