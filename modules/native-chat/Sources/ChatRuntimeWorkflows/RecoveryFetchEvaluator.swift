import ChatRuntimeModel
import Foundation
import OpenAITransport

/// The facts observed when a recovery fetch completes or fails.
public struct RecoveryFetchOutcome: Sendable {
    /// The transport fetch result, if the fetch succeeded.
    public let fetchResult: OpenAIResponseFetchResult?
    /// The error thrown by the transport, if the fetch failed.
    public let fetchError: (any Error)?
    /// Whether streaming resume is preferred (background mode).
    public let preferStreamingResume: Bool
    /// Whether the original request used background mode.
    public let usedBackgroundMode: Bool
    /// The last received event sequence number, if any.
    public let lastSequenceNumber: Int?

    /// Creates a recovery fetch outcome from a successful result.
    public init(
        result: OpenAIResponseFetchResult,
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) {
        self.fetchResult = result
        self.fetchError = nil
        self.preferStreamingResume = preferStreamingResume
        self.usedBackgroundMode = usedBackgroundMode
        self.lastSequenceNumber = lastSequenceNumber
    }

    /// Creates a recovery fetch outcome from a failed fetch.
    public init(
        error: any Error,
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) {
        self.fetchResult = nil
        self.fetchError = error
        self.preferStreamingResume = preferStreamingResume
        self.usedBackgroundMode = usedBackgroundMode
        self.lastSequenceNumber = lastSequenceNumber
    }
}

/// The runtime-decided action after a recovery fetch completes.
public enum RecoveryFetchAction: Sendable {
    /// Finish recovery using the fetched result (success or failed terminal).
    case finish(result: OpenAIResponseFetchResult, errorMessage: String?)
    /// Resume streaming from the given sequence number.
    case startStream(lastSequenceNumber: Int)
    /// Switch to polling for completion.
    case poll
    /// The error is unrecoverable — let composition handle it (may still fall back to poll).
    case handleError(error: any Error)
}

/// Pure-function evaluator for recovery fetch decisions.
///
/// Takes transport results and decides what the composition layer should do next,
/// without the composition layer needing to embed any recovery strategy logic.
public enum RecoveryFetchEvaluator {
    /// Evaluate a recovery fetch outcome and return the decided action.
    public static func evaluate(_ outcome: RecoveryFetchOutcome) -> RecoveryFetchAction {
        // If fetch failed, composition must handle the error
        if let error = outcome.fetchError {
            return .handleError(error: error)
        }

        guard let result = outcome.fetchResult else {
            return .poll
        }

        // Delegate to the existing planner (which delegates to RuntimeSessionDecisionPolicy)
        let plannerAction = ReplyRecoveryPlanner.fetchAction(
            for: result,
            preferStreamingResume: outcome.preferStreamingResume,
            usedBackgroundMode: outcome.usedBackgroundMode,
            lastSequenceNumber: outcome.lastSequenceNumber
        )

        switch plannerAction {
        case .finish(.completed):
            return .finish(result: result, errorMessage: nil)
        case let .finish(.failed(errorMessage)):
            return .finish(result: result, errorMessage: errorMessage)
        case let .startStream(lastSeq):
            return .startStream(lastSequenceNumber: lastSeq)
        case .poll:
            return .poll
        }
    }
}
