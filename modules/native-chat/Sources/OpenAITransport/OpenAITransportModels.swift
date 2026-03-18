import ChatDomain
import Foundation

public typealias APIMessage = ChatRequestMessage

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
