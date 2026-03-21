import Foundation

/// Determines how a recovery session should resume: by streaming or polling.
public enum RuntimeRecoveryResumeMode: Equatable, Sendable {
    /// Resume by streaming from the given sequence number.
    case stream(lastSequenceNumber: Int)
    /// Resume by polling for the completed response.
    case poll
}

/// Runtime-owned status vocabulary for detached response recovery.
public enum RuntimeRecoveryStatus: Equatable, Sendable {
    /// The response has not begun generating yet.
    case queued
    /// The response is still generating.
    case inProgress
    /// The response completed successfully.
    case completed
    /// The response terminated unsuccessfully or ambiguously.
    case failed
}

/// The next runtime-owned action after inspecting detached response status.
public enum RuntimeRecoveryFetchAction: Equatable, Sendable {
    /// Finish recovery and finalize the reply with the given terminal state.
    case finish(RuntimeRecoveryTerminalState)
    /// Resume recovery by streaming from the provided sequence number.
    case startStream(lastSequenceNumber: Int)
    /// Resume recovery by polling until the response reaches a terminal state.
    case poll
}

/// Terminal state reached by recovery.
public enum RuntimeRecoveryTerminalState: Equatable, Sendable {
    /// The detached response completed successfully.
    case completed
    /// The detached response did not complete successfully.
    case failed(String?)
}

/// The next runtime-owned step after a recovery stream exits without completion.
public enum RuntimeRecoveryStreamNextStep: Equatable, Sendable {
    /// Retry the recovery stream against the direct endpoint.
    case retryDirectStream
    /// Fall back to polling.
    case poll
    /// No additional recovery step is warranted.
    case none
}

/// Represents a pending cancellation request for a background response.
public struct RuntimePendingBackgroundCancellation: Equatable, Sendable {
    /// The API response identifier to cancel.
    public let responseId: String
    /// The message identifier associated with the cancellation.
    public let messageId: UUID

    /// Creates a new pending background cancellation.
    /// - Parameters:
    ///   - responseId: The API response identifier.
    ///   - messageId: The associated message identifier.
    public init(responseId: String, messageId: UUID) {
        self.responseId = responseId
        self.messageId = messageId
    }
}
