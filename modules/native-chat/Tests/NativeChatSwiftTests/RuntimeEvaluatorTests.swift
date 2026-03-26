import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing

struct RuntimeEvaluatorTests {
    @Test func `stream terminal evaluator recovers using runtime tracked response metadata`() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: "resp_tracked",
                pendingError: "stream failed",
                hasBufferContent: false,
                lastSequenceNumber: 12,
                usesBackgroundMode: true,
                canRetryConnection: false
            )
        )

        #expect(
            action == .recover(
                responseID: "resp_tracked",
                lastSequenceNumber: 12,
                usesBackgroundMode: true
            )
        )
    }

    @Test func `stream terminal evaluator retries connection before removing empty draft`() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: true
            )
        )

        #expect(action == .retryConnection)
    }

    @Test func `stream terminal evaluator finalizes partial buffer when recovery is unavailable`() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: true,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(action == .finalizePartial)
    }

    @Test func `recovery fetch evaluator starts stream when a resumable cursor exists`() {
        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: OpenAIResponseFetchResult(
                    status: .inProgress,
                    text: "",
                    thinking: nil,
                    annotations: [],
                    toolCalls: [],
                    filePathAnnotations: [],
                    errorMessage: nil
                ),
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 17
            )
        )

        switch action {
        case let .startStream(lastSequenceNumber):
            #expect(lastSequenceNumber == 17)
        default:
            Issue.record("Expected startStream action, got \(String(describing: action))")
        }
    }

    @Test func `recovery fetch evaluator preserves incomplete results as incomplete terminal state`() {
        let action = RecoveryFetchEvaluator.evaluate(
            RecoveryFetchOutcome(
                result: OpenAIResponseFetchResult(
                    status: .incomplete,
                    text: "Partial answer",
                    thinking: "Partial reasoning",
                    annotations: [],
                    toolCalls: [],
                    filePathAnnotations: [],
                    errorMessage: "Max tokens reached."
                ),
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 17
            )
        )

        switch action {
        case let .finish(result, errorMessage):
            #expect(result.status == .incomplete)
            #expect(result.text == "Partial answer")
            #expect(errorMessage == "Max tokens reached.")
        default:
            Issue.record("Expected finish action, got \(String(describing: action))")
        }
    }

    @Test func `recovery stream evaluator retries direct stream after gateway timeout`() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                resumeTimedOut: true,
                encounteredRecoverableFailure: true,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: "resp_gateway"
            )
        )

        #expect(action == .retryDirectStream)
    }

    @Test func `recovery stream evaluator gives up when no retry or polling path remains`() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                resumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: true,
                responseID: nil
            )
        )

        #expect(action == .giveUp)
    }

    @Test func `recovery poll evaluator continues polling after transient error`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                error: StubError.transient,
                attempt: 3,
                maxAttempts: RecoveryPollEvaluator.defaultMaxAttempts
            )
        )

        switch action {
        case let .continuePolling(delayNanoseconds):
            #expect(delayNanoseconds == 2_000_000_000)
        default:
            Issue.record("Expected continuePolling action, got \(String(describing: action))")
        }
    }

    @Test func `recovery poll evaluator finishes completed responses`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: OpenAIResponseFetchResult(
                    status: .completed,
                    text: "done",
                    thinking: nil,
                    annotations: [],
                    toolCalls: [],
                    filePathAnnotations: [],
                    errorMessage: nil
                ),
                attempt: 11,
                maxAttempts: RecoveryPollEvaluator.defaultMaxAttempts
            )
        )

        switch action {
        case let .terminal(result, errorMessage):
            #expect(result.status == .completed)
            #expect(errorMessage == nil)
        default:
            Issue.record("Expected terminal action, got \(String(describing: action))")
        }
    }
}

private enum StubError: Error {
    case transient
}
