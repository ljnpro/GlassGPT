import ChatDomain
import Foundation

/// Type alias mapping ``ChatRequestMessage`` to the transport layer's message type.
public typealias APIMessage = ChatRequestMessage

/// Events emitted during a streaming chat completion or recovery session.
public enum StreamEvent: Sendable {
    /// An incremental text content delta.
    case textDelta(String)
    /// A replacement text snapshot that supersedes previously streamed text.
    case replaceText(String)
    /// An incremental reasoning/thinking content delta.
    case thinkingDelta(String)
    /// The model has entered its thinking phase.
    case thinkingStarted
    /// The model has finished its thinking phase.
    case thinkingFinished
    /// A new response has been created with the given identifier.
    case responseCreated(String)
    /// The event sequence number has been updated.
    case sequenceUpdate(Int)
    /// The response completed successfully with full text, optional thinking, and optional file annotations.
    case completed(String, String?, [FilePathAnnotation]?)
    /// The response was incomplete with partial text, thinking, file annotations, and an optional message.
    case incomplete(String, String?, [FilePathAnnotation]?, String?)
    /// The network connection was lost during streaming.
    case connectionLost
    /// An error occurred during streaming.
    case error(OpenAIServiceError)

    /// A web search tool call has started with the given item ID.
    case webSearchStarted(String)
    /// A web search tool call is actively searching.
    case webSearchSearching(String)
    /// A web search tool call has completed.
    case webSearchCompleted(String)
    /// A code interpreter tool call has started.
    case codeInterpreterStarted(String)
    /// A code interpreter tool call is interpreting code.
    case codeInterpreterInterpreting(String)
    /// An incremental code delta for the given code interpreter call.
    case codeInterpreterCodeDelta(String, String)
    /// The full code for the given code interpreter call is complete.
    case codeInterpreterCodeDone(String, String)
    /// A code interpreter tool call has completed.
    case codeInterpreterCompleted(String)
    /// A file search tool call has started.
    case fileSearchStarted(String)
    /// A file search tool call is actively searching.
    case fileSearchSearching(String)
    /// A file search tool call has completed.
    case fileSearchCompleted(String)

    /// A URL citation annotation has been added.
    case annotationAdded(URLCitation)
    /// A file path annotation has been added.
    case filePathAnnotationAdded(FilePathAnnotation)
}

/// The result of fetching a completed or in-progress response from the API.
public struct OpenAIResponseFetchResult: Sendable, Equatable {
    /// The status of a fetched response.
    public enum Status: String, Sendable, Equatable {
        /// The response is waiting in the queue.
        case queued
        /// The response is currently being generated.
        case inProgress = "in_progress"
        /// The response has been fully generated.
        case completed
        /// The response generation failed.
        case failed
        /// The response was generated but is incomplete.
        case incomplete
        /// The response status is not recognized.
        case unknown
    }

    /// The current status of the response.
    public let status: Status
    /// The output text of the response.
    public let text: String
    /// The reasoning/thinking text, if available.
    public let thinking: String?
    /// URL citations referenced in the response.
    public let annotations: [URLCitation]
    /// Tool calls made during the response.
    public let toolCalls: [ToolCallInfo]
    /// File path annotations in the response.
    public let filePathAnnotations: [FilePathAnnotation]
    /// An error message, if the response failed.
    public let errorMessage: String?

    /// Creates a new response fetch result.
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
