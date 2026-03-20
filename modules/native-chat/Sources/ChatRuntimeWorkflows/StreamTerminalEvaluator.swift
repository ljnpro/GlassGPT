// PURE FUNCTION CONTRACT: This evaluator must remain a pure Outcome → Action
// mapper. It must NEVER hold service references, perform I/O, or read global state.

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
    /// The runtime state's current response ID, if any.
    public let stateResponseID: String?
    /// An error surfaced during the terminal or incomplete event.
    public let pendingError: String?
    /// Whether the reply buffer contains any assistant text.
    public let hasBufferContent: Bool
    /// The runtime state's last received sequence number, if any.
    public let lastSequenceNumber: Int?
    /// Whether the original request used background mode.
    public let usesBackgroundMode: Bool
    /// Whether a reconnect attempt is still available.
    public let canRetryConnection: Bool

    /// Creates a terminal outcome from the facts observed during a stream.
    public init(
        didComplete: Bool,
        connectionLost: Bool,
        pendingRecoveryResponseID: String?,
        stateResponseID: String?,
        pendingError: String?,
        hasBufferContent: Bool,
        lastSequenceNumber: Int?,
        usesBackgroundMode: Bool,
        canRetryConnection: Bool
    ) {
        self.didComplete = didComplete
        self.connectionLost = connectionLost
        self.pendingRecoveryResponseID = pendingRecoveryResponseID
        self.stateResponseID = stateResponseID
        self.pendingError = pendingError
        self.hasBufferContent = hasBufferContent
        self.lastSequenceNumber = lastSequenceNumber
        self.usesBackgroundMode = usesBackgroundMode
        self.canRetryConnection = canRetryConnection
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
    /// - Parameter outcome: The facts observed when the stream ended.
    /// - Returns: The decided action for composition to dispatch.
    public static func evaluate(_ outcome: StreamTerminalOutcome) -> StreamTerminalAction {
        // 1. Clean completion — nothing more to do.
        if outcome.didComplete {
            return .completed
        }

        // 2. We have a response ID for recovery (from pending recovery or current state).
        let recoveryResponseID = outcome.pendingRecoveryResponseID ?? outcome.stateResponseID
        if let responseID = recoveryResponseID {
            return .recover(
                responseID: responseID,
                lastSequenceNumber: outcome.lastSequenceNumber,
                usesBackgroundMode: outcome.usesBackgroundMode
            )
        }

        // 3. Connection lost with no response ID — try reconnecting first.
        if outcome.connectionLost && outcome.canRetryConnection {
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
