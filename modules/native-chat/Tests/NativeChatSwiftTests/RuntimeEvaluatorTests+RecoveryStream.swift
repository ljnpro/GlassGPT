import ChatRuntimeWorkflows
import Foundation
import Testing

/// Comprehensive edge-case tests for ``RecoveryStreamEvaluator``.
struct RecoveryStreamEvaluatorEdgeCaseTests {
    // MARK: - Completed

    @Test func `completed when finished from stream`() {
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

    @Test func `completed takes precedence over gateway timeout`() {
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

    @Test func `retry direct stream when gateway times out`() {
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

    @Test func `retry direct stream when no events received via gateway`() {
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

    @Test func `no retry direct stream when already using direct endpoint`() {
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

    @Test func `no retry direct stream when gateway disabled`() {
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

    @Test func `poll when recoverable failure with response ID`() {
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

    @Test func `poll when response ID available without recoverable failure`() {
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

    @Test func `give up when no retry and no polling path`() {
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

    @Test func `give up when direct endpoint and no recoverable failure and no response ID`() {
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

    @Test func `gateway enabled with events received and no timeout polls if has response ID`() {
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

    @Test func `gateway enabled with events received and no timeout gives up if no response ID`() {
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
