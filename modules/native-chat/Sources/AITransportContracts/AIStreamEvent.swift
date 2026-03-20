import ChatDomain
import Foundation

/// Provider-agnostic events emitted during a streaming AI completion or recovery session.
///
/// This enum mirrors the provider-specific stream event types but belongs to the
/// contracts layer, allowing runtime workflows to process stream events without
/// depending on a specific provider's transport module.
public enum AIStreamEvent: Sendable {
    /// An incremental text content delta.
    case textDelta(String)
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
    case error(AIServiceError)

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
