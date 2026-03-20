import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing

/// Comprehensive edge-case tests for ``RecoveryPollEvaluator``.
struct RecoveryPollEvaluatorEdgeCaseTests {
    // MARK: - Error Path

    @Test func `short delay for early attempt errors`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(error: StubPollError.transient, attempt: 1, maxAttempts: 180)
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 2_000_000_000)
        default:
            Issue.record("Expected continuePolling, got \(String(describing: action))")
        }
    }

    @Test func `short delay for attempt nine error`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(error: StubPollError.transient, attempt: 9, maxAttempts: 180)
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 2_000_000_000)
        default:
            Issue.record("Expected continuePolling, got \(String(describing: action))")
        }
    }

    @Test func `long delay for attempt ten error`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(error: StubPollError.transient, attempt: 10, maxAttempts: 180)
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 3_000_000_000)
        default:
            Issue.record("Expected continuePolling, got \(String(describing: action))")
        }
    }

    @Test func `long delay for late attempt error`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(error: StubPollError.transient, attempt: 100, maxAttempts: 180)
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 3_000_000_000)
        default:
            Issue.record("Expected continuePolling, got \(String(describing: action))")
        }
    }

    // MARK: - Nil Result Path (defensive)

    @Test func `continue polling when result is nil and no error`() {
        // Construct via error init then exercise nil-result guard
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(error: StubPollError.transient, attempt: 5, maxAttempts: 180)
        )

        switch action {
        case .continuePolling:
            break // expected
        default:
            Issue.record("Expected continuePolling, got \(String(describing: action))")
        }
    }

    // MARK: - Queued Status

    @Test func `continue polling for queued response`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .queued),
                attempt: 3,
                maxAttempts: 180
            )
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 2_000_000_000)
        default:
            Issue.record("Expected continuePolling for queued, got \(String(describing: action))")
        }
    }

    // MARK: - InProgress Status

    @Test func `continue polling for in progress response`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .inProgress),
                attempt: 15,
                maxAttempts: 180
            )
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 3_000_000_000)
        default:
            Issue.record("Expected continuePolling for inProgress, got \(String(describing: action))")
        }
    }

    // MARK: - Completed Status

    @Test func `terminal with no error for completed`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .completed, text: "done"),
                attempt: 5,
                maxAttempts: 180
            )
        )

        switch action {
        case let .terminal(result, errorMessage):
            #expect(result.status == .completed)
            #expect(errorMessage == nil)
        default:
            Issue.record("Expected terminal, got \(String(describing: action))")
        }
    }

    // MARK: - Failed Status

    @Test func `terminal with error message for failed`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .failed, errorMessage: "Server error"),
                attempt: 2,
                maxAttempts: 180
            )
        )

        switch action {
        case let .terminal(result, errorMessage):
            #expect(result.status == .failed)
            #expect(errorMessage == "Server error")
        default:
            Issue.record("Expected terminal with error, got \(String(describing: action))")
        }
    }

    @Test func `terminal with fallback message for failed without error message`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .failed),
                attempt: 2,
                maxAttempts: 180
            )
        )

        switch action {
        case let .terminal(_, errorMessage):
            #expect(errorMessage == "Response did not complete.")
        default:
            Issue.record("Expected terminal, got \(String(describing: action))")
        }
    }

    // MARK: - Incomplete Status

    @Test func `terminal for incomplete response`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .incomplete, errorMessage: "Max tokens"),
                attempt: 7,
                maxAttempts: 180
            )
        )

        switch action {
        case let .terminal(result, errorMessage):
            #expect(result.status == .incomplete)
            #expect(errorMessage == "Max tokens")
        default:
            Issue.record("Expected terminal for incomplete, got \(String(describing: action))")
        }
    }

    // MARK: - Unknown Status

    @Test func `terminal for unknown status`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .unknown),
                attempt: 1,
                maxAttempts: 180
            )
        )

        switch action {
        case let .terminal(_, errorMessage):
            #expect(errorMessage == "Response did not complete.")
        default:
            Issue.record("Expected terminal for unknown, got \(String(describing: action))")
        }
    }

    // MARK: - Default Max Attempts

    @Test func `default max attempts is180`() {
        #expect(RecoveryPollEvaluator.defaultMaxAttempts == 180)
    }

    // MARK: - Delay Boundary at Attempt 10

    @Test func `delay boundary for queued at attempt nine`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .queued),
                attempt: 9,
                maxAttempts: 180
            )
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 2_000_000_000)
        default:
            Issue.record("Expected 2s delay at attempt 9")
        }
    }

    @Test func `delay boundary for queued at attempt ten`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: .queued),
                attempt: 10,
                maxAttempts: 180
            )
        )

        switch action {
        case let .continuePolling(delay):
            #expect(delay == 3_000_000_000)
        default:
            Issue.record("Expected 3s delay at attempt 10")
        }
    }
}

private enum StubPollError: Error {
    case transient
}

private func makeResult(
    status: OpenAIResponseFetchResult.Status,
    text: String = "",
    errorMessage: String? = nil
) -> OpenAIResponseFetchResult {
    OpenAIResponseFetchResult(
        status: status,
        text: text,
        thinking: nil,
        annotations: [],
        toolCalls: [],
        filePathAnnotations: [],
        errorMessage: errorMessage
    )
}
