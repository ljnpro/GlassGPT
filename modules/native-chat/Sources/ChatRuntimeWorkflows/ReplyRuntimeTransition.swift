import ChatDomain
import ChatRuntimeModel
import Foundation

/// Discrete state transitions that can be applied to a reply session.
///
/// Each case represents an atomic mutation to the ``ReplyRuntimeState``,
/// processed by ``ReplySessionActor``.
public enum ReplyRuntimeTransition: Sendable, Equatable {
    /// Transition to the preparing-input phase.
    case beginSubmitting
    /// Transition to the attachment-upload phase.
    case beginUploadingAttachments
    /// Begin streaming with the given stream identifier and transport route.
    case beginStreaming(streamID: UUID, route: OpenAITransportRoute)
    /// Record that the API has created a response with the given ID and route.
    case recordResponseCreated(String, route: OpenAITransportRoute)
    /// Update the cursor with a new event sequence number.
    case recordSequenceUpdate(Int)
    /// Append a text delta to the reply buffer.
    case appendText(String)
    /// Append a thinking/reasoning delta to the reply buffer.
    case appendThinking(String)
    /// Set whether the model is currently in its thinking phase.
    case setThinking(Bool)
    /// Start tracking a new tool call with the given identifier and type.
    case startToolCall(id: String, type: ToolCallType)
    /// Update the status of an existing tool call.
    case setToolCallStatus(id: String, status: ToolCallStatus)
    /// Append a code delta to an existing tool call.
    case appendToolCode(id: String, delta: String)
    /// Replace the code of an existing tool call.
    case setToolCode(id: String, code: String)
    /// Add a URL citation to the reply buffer.
    case addCitation(URLCitation)
    /// Add a file path annotation to the reply buffer.
    case addFilePathAnnotation(FilePathAnnotation)
    /// Merge a terminal (completed) payload into the buffer, replacing content if non-empty.
    case mergeTerminalPayload(text: String, thinking: String?, filePathAnnotations: [FilePathAnnotation]?)
    /// Begin recovery by checking the status of a detached response.
    case beginRecoveryStatus(
        responseID: String,
        lastSequenceNumber: Int?,
        usedBackgroundMode: Bool,
        route: OpenAITransportRoute
    )
    /// Begin recovery by resuming a stream with the given stream identifier.
    case beginRecoveryStream(streamID: UUID)
    /// Begin recovery by polling for the completed response.
    case beginRecoveryPoll
    /// Detach the reply for background processing.
    case detachForBackground(usedBackgroundMode: Bool)
    /// Cancel the active streaming session.
    case cancelStreaming
    /// Transition to the finalizing phase.
    case beginFinalizing
    /// Mark the reply as successfully completed.
    case markCompleted
    /// Mark the reply as failed with an optional error message.
    case markFailed(String?)
}
