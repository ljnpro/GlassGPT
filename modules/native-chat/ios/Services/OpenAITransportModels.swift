import Foundation

// MARK: - Sendable DTOs for transport layer

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

// MARK: - Errors

enum OpenAIServiceError: Error, Sendable, LocalizedError {
    case noAPIKey
    case invalidURL
    case httpError(Int, String)
    case requestFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add it in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .httpError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .requestFailed(let msg):
            return msg
        case .cancelled:
            return "Request was cancelled."
        }
    }
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
