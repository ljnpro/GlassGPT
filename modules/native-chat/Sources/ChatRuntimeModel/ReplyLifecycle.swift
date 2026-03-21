import Foundation

/// The lifecycle phases of an assistant reply, from idle through completion or failure.
public enum ReplyLifecycle: Equatable, Sendable {
    /// No reply is active.
    case idle
    /// User input is being prepared for submission.
    case preparingInput
    /// File attachments are being uploaded before streaming.
    case uploadingAttachments
    /// The reply is actively streaming from the given cursor position.
    case streaming(StreamCursor)
    /// The reply has been detached for background processing.
    case detached(DetachedRecoveryTicket)
    /// Recovery is checking the status of a detached reply.
    case recoveringStatus(DetachedRecoveryTicket)
    /// Recovery is resuming a stream from a cursor position.
    case recoveringStream(StreamCursor)
    /// Recovery is polling for completion of a detached reply.
    case recoveringPoll(DetachedRecoveryTicket)
    /// The reply content is being finalized and persisted.
    case finalizing
    /// The reply has been completed successfully.
    case completed
    /// The reply failed with an optional error message.
    case failed(String?)
}
