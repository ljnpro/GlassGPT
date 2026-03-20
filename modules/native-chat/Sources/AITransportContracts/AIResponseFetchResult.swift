import ChatDomain
import Foundation

/// Provider-agnostic result of fetching a completed or in-progress AI response.
///
/// This type decouples runtime evaluators and recovery planners from
/// provider-specific transport types.
public struct AIResponseFetchResult: Sendable, Equatable {
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
