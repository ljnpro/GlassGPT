import ChatDomain
import Foundation

/// The full runtime state of an active assistant reply session.
public struct ReplyRuntimeState: Equatable, Sendable {
    /// The runtime identifier for this reply.
    public let assistantReplyID: AssistantReplyID
    /// The persisted message identifier.
    public let messageID: UUID
    /// The owning conversation identifier.
    public let conversationID: UUID
    /// The current lifecycle phase of this reply.
    public var lifecycle: ReplyLifecycle
    /// The buffer accumulating streamed content.
    public var buffer: ReplyBuffer
    /// Whether the model is currently in its thinking/reasoning phase.
    public var isThinking: Bool
    /// Whether the active recovery flow originated from a background-mode request.
    public var recoveryUsesBackgroundMode: Bool?
    /// Whether a restarted recovery reply should keep showing recovery UI until live progress resumes.
    public var pendingRecoveryRestart: Bool

    /// Creates a new reply runtime state.
    /// - Parameters:
    ///   - assistantReplyID: The runtime reply identifier.
    ///   - messageID: The persisted message identifier.
    ///   - conversationID: The conversation identifier.
    ///   - lifecycle: The initial lifecycle phase. Defaults to `.idle`.
    ///   - buffer: The initial reply buffer. Defaults to empty.
    ///   - isThinking: Whether the model is thinking. Defaults to `false`.
    ///   - recoveryUsesBackgroundMode: Whether a recovery flow should retain background-mode semantics.
    ///   - pendingRecoveryRestart: Whether a restarted recovery request is waiting for new live progress.
    public init(
        assistantReplyID: AssistantReplyID,
        messageID: UUID,
        conversationID: UUID,
        lifecycle: ReplyLifecycle = .idle,
        buffer: ReplyBuffer = .init(),
        isThinking: Bool = false,
        recoveryUsesBackgroundMode: Bool? = nil,
        pendingRecoveryRestart: Bool = false
    ) {
        self.assistantReplyID = assistantReplyID
        self.messageID = messageID
        self.conversationID = conversationID
        self.lifecycle = lifecycle
        self.buffer = buffer
        self.isThinking = isThinking
        self.recoveryUsesBackgroundMode = recoveryUsesBackgroundMode
        self.pendingRecoveryRestart = pendingRecoveryRestart
    }

    /// The stream cursor derived from the current lifecycle state, or `nil` if not streaming.
    public var cursor: StreamCursor? {
        switch lifecycle {
        case let .streaming(cursor), let .recoveringStream(cursor):
            cursor
        case let .recoveringStatus(ticket), let .recoveringPoll(ticket), let .detached(ticket):
            StreamCursor(
                responseID: ticket.responseID,
                lastSequenceNumber: ticket.lastSequenceNumber,
                route: ticket.route
            )
        case .idle, .preparingInput, .uploadingAttachments, .finalizing, .completed, .failed:
            nil
        }
    }

    /// The API response identifier from the current cursor, if available.
    public var responseID: String? {
        cursor?.responseID
    }

    /// The last received sequence number from the current cursor, if available.
    public var lastSequenceNumber: Int? {
        cursor?.lastSequenceNumber
    }

    /// Whether the reply is actively receiving streamed content.
    public var isStreaming: Bool {
        switch lifecycle {
        case .streaming, .recoveringStream:
            true
        case .idle, .preparingInput, .uploadingAttachments, .detached, .recoveringStatus, .recoveringPoll, .finalizing, .completed, .failed:
            false
        }
    }

    /// Whether the reply is in a recovery phase.
    public var isRecovering: Bool {
        switch lifecycle {
        case .recoveringStatus, .recoveringStream, .recoveringPoll:
            true
        case .idle, .preparingInput, .uploadingAttachments, .streaming, .detached, .finalizing, .completed, .failed:
            false
        }
    }
}
