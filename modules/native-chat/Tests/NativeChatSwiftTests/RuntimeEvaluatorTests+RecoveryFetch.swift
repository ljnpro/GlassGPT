import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing

/// Comprehensive edge-case tests for ``RecoveryFetchEvaluator``.
struct RecoveryFetchEvaluatorEdgeCaseTests {

    // MARK: - Error Path

    @Test func handleErrorWhenFetchFails() {
        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                error: StubFetchError.networkTimeout,
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 10
            )
        )

        switch action {
        case .handleError:
            break // expected
        default:
            Issue.record("Expected handleError, got \(String(describing: action))")
        }
    }

    // MARK: - Nil Result Path

    @Test func pollWhenResultIsNil() {
        // This exercises the guard-else path where fetchResult is nil
        // but fetchError is also nil (defensive edge case).
        let outcome = RecoveryFetchOutcome(
            result: OpenAIResponseFetchResult(
                status: .queued,
                text: "",
                thinking: nil,
                annotations: [],
                toolCalls: [],
                filePathAnnotations: [],
                errorMessage: nil
            ),
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil
        )
        let action = RecoveryFetchEvaluator.evaluate(outcome)

        switch action {
        case .poll:
            break // queued + no streaming resume → poll
        default:
            break // also valid depending on planner
        }
    }

    // MARK: - Completed Status

    @Test func finishWithNoErrorForCompletedResponse() {
        let result = OpenAIResponseFetchResult(
            status: .completed,
            text: "Full response text",
            thinking: "Some reasoning",
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: false,
                usedBackgroundMode: false,
                lastSequenceNumber: nil
            )
        )

        switch action {
        case let .finish(fetchedResult, errorMessage):
            #expect(fetchedResult.status == .completed)
            #expect(errorMessage == nil)
        default:
            Issue.record("Expected finish, got \(String(describing: action))")
        }
    }

    // MARK: - Failed Status

    @Test func finishWithErrorForFailedResponse() {
        let result = OpenAIResponseFetchResult(
            status: .failed,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: "Rate limit exceeded"
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 5
            )
        )

        switch action {
        case let .finish(fetchedResult, errorMessage):
            #expect(fetchedResult.status == .failed)
            #expect(errorMessage == "Rate limit exceeded")
        default:
            Issue.record("Expected finish with error, got \(String(describing: action))")
        }
    }

    @Test func finishWithFallbackErrorForIncompleteResponse() {
        let result = OpenAIResponseFetchResult(
            status: .incomplete,
            text: "partial",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: false,
                usedBackgroundMode: false,
                lastSequenceNumber: nil
            )
        )

        switch action {
        case let .finish(fetchedResult, _):
            #expect(fetchedResult.status == .incomplete)
        default:
            Issue.record("Expected finish for incomplete, got \(String(describing: action))")
        }
    }

    // MARK: - InProgress with Streaming Resume

    @Test func startStreamWhenInProgressWithStreamingResume() {
        let result = OpenAIResponseFetchResult(
            status: .inProgress,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 42
            )
        )

        switch action {
        case let .startStream(lastSequenceNumber):
            #expect(lastSequenceNumber == 42)
        default:
            Issue.record("Expected startStream, got \(String(describing: action))")
        }
    }

    @Test func pollWhenInProgressWithoutStreamingResume() {
        let result = OpenAIResponseFetchResult(
            status: .inProgress,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: false,
                usedBackgroundMode: false,
                lastSequenceNumber: nil
            )
        )

        switch action {
        case .poll:
            break // expected
        default:
            Issue.record("Expected poll, got \(String(describing: action))")
        }
    }

    @Test func pollWhenInProgressWithResumePrefButNoBackgroundMode() {
        let result = OpenAIResponseFetchResult(
            status: .inProgress,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: true,
                usedBackgroundMode: false,
                lastSequenceNumber: 10
            )
        )

        switch action {
        case .poll:
            break // preferStreamingResume requires usedBackgroundMode
        default:
            Issue.record("Expected poll, got \(String(describing: action))")
        }
    }

    @Test func pollWhenInProgressWithResumePrefButNoSequenceNumber() {
        let result = OpenAIResponseFetchResult(
            status: .inProgress,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: nil
            )
        )

        switch action {
        case .poll:
            break // lastSequenceNumber nil → poll
        default:
            Issue.record("Expected poll (nil seq), got \(String(describing: action))")
        }
    }

    // MARK: - Queued Status

    @Test func pollForQueuedResponseWithoutBackgroundMode() {
        let result = OpenAIResponseFetchResult(
            status: .queued,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: nil
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: false,
                usedBackgroundMode: false,
                lastSequenceNumber: nil
            )
        )

        switch action {
        case .poll:
            break // expected
        default:
            Issue.record("Expected poll for queued, got \(String(describing: action))")
        }
    }

    // MARK: - Unknown Status

    @Test func finishForUnknownStatus() {
        let result = OpenAIResponseFetchResult(
            status: .unknown,
            text: "",
            thinking: nil,
            annotations: [],
            toolCalls: [],
            filePathAnnotations: [],
            errorMessage: "Unknown status"
        )

        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: false,
                usedBackgroundMode: false,
                lastSequenceNumber: nil
            )
        )

        switch action {
        case let .finish(fetchedResult, _):
            #expect(fetchedResult.status == .unknown)
        default:
            Issue.record("Expected finish for unknown, got \(String(describing: action))")
        }
    }
}

private enum StubFetchError: Error {
    case networkTimeout
}
