import ChatRuntimeModel
import Foundation
import OpenAITransport

/// The observed state of a single polling attempt.
public struct PollAttemptOutcome: Sendable {
    /// The fetch result, if the poll succeeded.
    public let result: OpenAIResponseFetchResult?
    /// The error, if the poll failed.
    public let error: (any Error)?
    /// The current attempt number (1-based).
    public let attempt: Int
    /// The maximum number of attempts before giving up.
    public let maxAttempts: Int

    /// Creates a successful poll attempt outcome.
    public init(result: OpenAIResponseFetchResult, attempt: Int, maxAttempts: Int) {
        self.result = result
        self.error = nil
        self.attempt = attempt
        self.maxAttempts = maxAttempts
    }

    /// Creates a failed poll attempt outcome.
    public init(error: any Error, attempt: Int, maxAttempts: Int) {
        self.result = nil
        self.error = error
        self.attempt = attempt
        self.maxAttempts = maxAttempts
    }
}

/// The runtime-decided action for each polling iteration.
public enum PollStepAction: Sendable {
    /// Continue polling after a delay.
    case continuePolling(delayNanoseconds: UInt64)
    /// The response reached a terminal status — finish recovery.
    case terminal(result: OpenAIResponseFetchResult, errorMessage: String?)
    /// The error is unrecoverable — stop polling and let composition handle it.
    case unrecoverableError(error: any Error)
}

/// Pure-function evaluator for individual polling steps.
///
/// Owns the decision of whether to continue polling, finish, or abort.
/// The composition coordinator drives the loop; this evaluator decides
/// each step's outcome.
public enum RecoveryPollEvaluator {
    /// The default maximum number of poll attempts.
    public static let defaultMaxAttempts = 180

    /// Evaluate a single poll attempt and return the decided step action.
    public static func evaluate(_ outcome: PollAttemptOutcome) -> PollStepAction {
        // Error path
        if outcome.error != nil {
            let delay: UInt64 = outcome.attempt < 10 ? 2_000_000_000 : 3_000_000_000
            return .continuePolling(delayNanoseconds: delay)
        }

        guard let result = outcome.result else {
            let delay: UInt64 = outcome.attempt < 10 ? 2_000_000_000 : 3_000_000_000
            return .continuePolling(delayNanoseconds: delay)
        }

        switch result.status {
        case .queued, .inProgress:
            let delay: UInt64 = outcome.attempt < 10 ? 2_000_000_000 : 3_000_000_000
            return .continuePolling(delayNanoseconds: delay)

        case .completed:
            return .terminal(result: result, errorMessage: nil)

        case .incomplete, .failed, .unknown:
            return .terminal(
                result: result,
                errorMessage: result.errorMessage ?? "Response did not complete."
            )
        }
    }
}
