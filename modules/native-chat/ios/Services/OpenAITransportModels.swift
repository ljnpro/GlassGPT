import Foundation
import OpenAITransport

// MARK: - Sendable DTOs for transport layer

typealias OpenAIServiceError = OpenAITransport.OpenAIServiceError

struct APIMessage: Sendable {
    let role: MessageRole
    let content: String
    let imageData: Data?
    let fileAttachments: [FileAttachment]

    init(role: MessageRole, content: String, imageData: Data? = nil, fileAttachments: [FileAttachment] = []) {
        self.role = role
        self.content = content
        self.imageData = imageData
        self.fileAttachments = fileAttachments
    }
}

// MARK: - Stream Events

enum StreamEvent: Sendable {
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

// MARK: - Polling Fetch Result

struct OpenAIResponseFetchResult {
    enum Status: String, Sendable {
        case queued
        case inProgress = "in_progress"
        case completed
        case failed
        case incomplete
        case unknown
    }

    let status: Status
    let text: String
    let thinking: String?
    let annotations: [URLCitation]
    let toolCalls: [ToolCallInfo]
    let filePathAnnotations: [FilePathAnnotation]
    let errorMessage: String?
}
