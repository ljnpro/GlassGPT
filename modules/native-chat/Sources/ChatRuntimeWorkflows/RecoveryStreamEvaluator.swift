import ChatRuntimeModel
import Foundation

/// The facts observed when a recovery stream exits.
public struct RecoveryStreamOutcome: Sendable, Equatable {
    /// Whether the stream completed with a terminal success event.
    public let finishedFromStream: Bool
    /// Whether any recovery event was received before the stream ended.
    public let receivedAnyEvent: Bool
    /// Whether the gateway resume attempt timed out.
    public let gatewayResumeTimedOut: Bool
    /// Whether the stream encountered a recoverable failure.
    public let encounteredRecoverableFailure: Bool
    /// Whether Cloudflare gateway is enabled.
    public let cloudflareGatewayEnabled: Bool
    /// Whether the direct endpoint was already in use.
    public let useDirectEndpoint: Bool
    /// The response ID tracked by runtime state, if any.
    public let responseID: String?

    /// Creates a recovery stream outcome.
    public init(
        finishedFromStream: Bool,
        receivedAnyEvent: Bool,
        gatewayResumeTimedOut: Bool,
        encounteredRecoverableFailure: Bool,
        cloudflareGatewayEnabled: Bool,
        useDirectEndpoint: Bool,
        responseID: String?
    ) {
        self.finishedFromStream = finishedFromStream
        self.receivedAnyEvent = receivedAnyEvent
        self.gatewayResumeTimedOut = gatewayResumeTimedOut
        self.encounteredRecoverableFailure = encounteredRecoverableFailure
        self.cloudflareGatewayEnabled = cloudflareGatewayEnabled
        self.useDirectEndpoint = useDirectEndpoint
        self.responseID = responseID
    }
}

/// The runtime-decided action after a recovery stream exits.
public enum RecoveryStreamAction: Sendable, Equatable {
    /// The stream completed successfully — no further action needed.
    case completed
    /// Retry the stream using the direct endpoint (gateway timed out).
    case retryDirectStream
    /// Switch to polling for completion.
    case poll
    /// No further recovery is possible — give up.
    case giveUp
}

/// Pure-function evaluator for recovery stream decisions.
///
/// Owns the decision of what to do when a recovery stream ends without
/// a terminal completion event.
public enum RecoveryStreamEvaluator {
    /// Evaluate a recovery stream outcome and return the decided action.
    public static func evaluate(_ outcome: RecoveryStreamOutcome) -> RecoveryStreamAction {
        if outcome.finishedFromStream {
            return .completed
        }

        let plannerStep = ReplyRecoveryPlanner.streamNextStep(
            cloudflareGatewayEnabled: outcome.cloudflareGatewayEnabled,
            useDirectEndpoint: outcome.useDirectEndpoint,
            gatewayResumeTimedOut: outcome.gatewayResumeTimedOut,
            receivedAnyRecoveryEvent: outcome.receivedAnyEvent,
            encounteredRecoverableFailure: outcome.encounteredRecoverableFailure,
            responseId: outcome.responseID
        )

        switch plannerStep {
        case .retryDirectStream:
            return .retryDirectStream
        case .poll:
            return .poll
        case .none:
            return .giveUp
        }
    }
}
