import ChatRuntimeModel
import Foundation

/// The raw outcomes observed when a streaming event loop exits.
///
/// Composition collects these facts during the stream; the evaluator
/// turns them into a decision without needing access to external services.
public struct StreamTerminalOutcome: Sendable, Equatable {
    /// Whether the stream emitted a `response.completed` terminal event.
    public let didComplete: Bool
    /// Whether the transport reported a connection loss before the stream ended.
    public let connectionLost: Bool
    /// A response ID discovered during the stream that enables recovery.
    public let pendingRecoveryResponseID: String?
    /// An error surfaced during the terminal or incomplete event.
    public let pendingError: String?
    /// Whether the reply buffer contains any assistant text.
    public let hasBufferContent: Bool
    /// Whether the session was still in a streaming lifecycle when the loop exited.
    public let wasStillStreaming: Bool

    /// Creates a terminal outcome from the facts observed during a stream.
    public init(
        didComplete: Bool,
        connectionLost: Bool,
        pendingRecoveryResponseID: String?,
        pendingError: String?,
        hasBufferContent: Bool,
        wasStillStreaming: Bool
    ) {
        self.didComplete = didComplete
        self.connectionLost = connectionLost
        self.pendingRecoveryResponseID = pendingRecoveryResponseID
        self.pendingError = pendingError
        self.hasBufferContent = hasBufferContent
        self.wasStillStreaming = wasStillStreaming
    }
}

/// The runtime-decided action that composition should take after a stream ends.
///
/// This type replaces the decision tree that previously lived in the composition
/// layer. The evaluator owns the decision; composition only dispatches.
public enum StreamTerminalAction: Sendable, Equatable {
    /// The stream completed successfully — finalize and clean up.
    case completed
    /// The stream ended with a recoverable response — begin recovery.
    case recover(responseID: String, lastSequenceNumber: Int?, usesBackgroundMode: Bool)
    /// The stream ended with partial content — save what we have.
    case finalizePartial
    /// The stream ended with nothing — remove the empty draft message.
    case removeEmptyMessage(errorMessage: String?)
    /// The stream ended but a reconnect attempt should be tried first.
    case retryConnection
}

/// Pure-function evaluator that decides the next action after a stream ends.
///
/// This is the authoritative decision point for post-stream behavior.
/// It lives in the runtime layer so that composition coordinators do not
/// embed terminal-condition logic.
public enum StreamTerminalEvaluator {
    /// Evaluate a terminal outcome and return the action composition should take.
    ///
    /// - Parameters:
    ///   - outcome: The facts observed when the stream ended.
    ///   - state: The current runtime state snapshot.
    ///   - usesBackgroundMode: Whether the original request used background mode.
    ///   - canRetryConnection: Whether a reconnect attempt is still available.
    /// - Returns: The decided action for composition to dispatch.
    public static func evaluate(
        outcome: StreamTerminalOutcome,
        state: ReplyRuntimeState,
        usesBackgroundMode: Bool,
        canRetryConnection: Bool
    ) -> StreamTerminalAction {
        // 1. Clean completion — nothing more to do.
        if outcome.didComplete {
            return .completed
        }

        // 2. We have a response ID for recovery (from pending recovery or current state).
        let recoveryResponseID = outcome.pendingRecoveryResponseID ?? state.responseID
        if let responseID = recoveryResponseID {
            return .recover(
                responseID: responseID,
                lastSequenceNumber: state.lastSequenceNumber,
                usesBackgroundMode: usesBackgroundMode
            )
        }

        // 3. Connection lost with no response ID — try reconnecting first.
        if outcome.connectionLost && canRetryConnection {
            return .retryConnection
        }

        // 4. We have partial content — save it.
        if outcome.hasBufferContent {
            return .finalizePartial
        }

        // 5. Nothing received — remove the empty message.
        let errorMessage = outcome.pendingError
            ?? (outcome.connectionLost
                ? "Connection lost. Please check your network and try again."
                : nil)
        return .removeEmptyMessage(errorMessage: errorMessage)
    }
}
