import ChatRuntimeWorkflows
import Foundation
import Testing

/// Comprehensive edge-case tests for ``RecoveryStreamEvaluator``.
struct RecoveryStreamEvaluatorEdgeCaseTests {

    // MARK: - Completed

    @Test func completedWhenFinishedFromStream() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: true,
                receivedAnyEvent: true,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: "resp_123"
            )
        )

        #expect(action == .completed)
    }

    @Test func completedTakesPrecedenceOverGatewayTimeout() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: true,
                receivedAnyEvent: false,
                gatewayResumeTimedOut: true,
                encounteredRecoverableFailure: true,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: "resp_123"
            )
        )

        #expect(action == .completed)
    }

    // MARK: - Retry Direct Stream (Gateway Fallback)

    @Test func retryDirectStreamWhenGatewayTimesOut() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                gatewayResumeTimedOut: true,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: "resp_gw"
            )
        )

        #expect(action == .retryDirectStream)
    }

    @Test func retryDirectStreamWhenNoEventsReceivedViaGateway() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: "resp_no_events"
            )
        )

        #expect(action == .retryDirectStream)
    }

    @Test func noRetryDirectStreamWhenAlreadyUsingDirectEndpoint() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                gatewayResumeTimedOut: true,
                encounteredRecoverableFailure: true,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: true,
                responseID: "resp_direct"
            )
        )

        // Already on direct → should poll or give up, not retry direct
        #expect(action != .retryDirectStream)
    }

    @Test func noRetryDirectStreamWhenGatewayDisabled() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                gatewayResumeTimedOut: true,
                encounteredRecoverableFailure: true,
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: false,
                responseID: "resp_no_gw"
            )
        )

        #expect(action != .retryDirectStream)
    }

    // MARK: - Poll Fallback

    @Test func pollWhenRecoverableFailureWithResponseID() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: true,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: true,
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: true,
                responseID: "resp_poll"
            )
        )

        #expect(action == .poll)
    }

    @Test func pollWhenResponseIDAvailableWithoutRecoverableFailure() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: true,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: true,
                responseID: "resp_has_id"
            )
        )

        #expect(action == .poll)
    }

    // MARK: - Give Up

    @Test func giveUpWhenNoRetryAndNoPollingPath() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: true,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: true,
                responseID: nil
            )
        )

        #expect(action == .giveUp)
    }

    @Test func giveUpWhenDirectEndpointAndNoRecoverableFailureAndNoResponseID() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: false,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: false,
                useDirectEndpoint: true,
                responseID: nil
            )
        )

        #expect(action == .giveUp)
    }

    // MARK: - Gateway Matrix Combinations

    @Test func gatewayEnabledWithEventsReceivedAndNoTimeoutPollsIfHasResponseID() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: true,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: "resp_gw_events"
            )
        )

        // Events received + no timeout → no direct retry, but has responseID → poll
        #expect(action == .poll)
    }

    @Test func gatewayEnabledWithEventsReceivedAndNoTimeoutGivesUpIfNoResponseID() {
        let action = RecoveryStreamEvaluator.evaluate(
            RecoveryStreamOutcome(
                finishedFromStream: false,
                receivedAnyEvent: true,
                gatewayResumeTimedOut: false,
                encounteredRecoverableFailure: false,
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                responseID: nil
            )
        )

        #expect(action == .giveUp)
    }
}
