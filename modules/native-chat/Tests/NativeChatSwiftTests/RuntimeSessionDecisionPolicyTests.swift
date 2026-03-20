import ChatRuntimeModel
import Foundation
import Testing

/// Comprehensive tests for ``RuntimeSessionDecisionPolicy``.
struct RuntimeSessionDecisionPolicyTests {
    // MARK: - Recovery Resume Mode

    @Test func `stream resume when all conditions met`() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        #expect(mode == .stream(lastSequenceNumber: 42))
    }

    @Test func `poll when not preferring stream resume`() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: false,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        #expect(mode == .poll)
    }

    @Test func `poll when not using background mode`() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 42
        )

        #expect(mode == .poll)
    }

    @Test func `poll when no last sequence number`() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: nil
        )

        #expect(mode == .poll)
    }

    // MARK: - Recovery Fetch Action

    @Test func `finish completed for completed status`() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .completed,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: nil
        )

        #expect(action == .finish(.completed))
    }

    @Test func `finish failed with error message`() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .failed,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: "Rate limit"
        )

        #expect(action == .finish(.failed("Rate limit")))
    }

    @Test func `finish failed with nil error message`() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .failed,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: nil
        )

        #expect(action == .finish(.failed(nil)))
    }

    @Test func `start stream for in progress with all resume conditions`() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .inProgress,
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 17,
            errorMessage: nil
        )

        #expect(action == .startStream(lastSequenceNumber: 17))
    }

    @Test func `poll for queued without resume conditions`() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .queued,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: nil
        )

        #expect(action == .poll)
    }

    @Test func `poll for in progress without background mode`() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .inProgress,
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 10,
            errorMessage: nil
        )

        #expect(action == .poll)
    }

    // MARK: - Should Fallback to Direct Recovery Stream

    @Test func `fallback when gateway timed out`() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: true
        )

        #expect(result == true)
    }

    @Test func `fallback when no events received`() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: false
        )

        #expect(result == true)
    }

    @Test func `no fallback when already direct`() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: true,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: false
        )

        #expect(result == false)
    }

    @Test func `no fallback when gateway disabled`() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: false,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: false
        )

        #expect(result == false)
    }

    @Test func `no fallback when events received and no timeout`() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: true
        )

        #expect(result == false)
    }

    // MARK: - Should Poll After Recovery Stream

    @Test func `poll when recoverable failure`() {
        let result = RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: true,
            responseId: nil
        )

        #expect(result == true)
    }

    @Test func `poll when response ID present`() {
        let result = RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: false,
            responseId: "resp_123"
        )

        #expect(result == true)
    }

    @Test func `no poll when no failure and no response ID`() {
        let result = RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: false,
            responseId: nil
        )

        #expect(result == false)
    }

    // MARK: - Recovery Stream Next Step

    @Test func `retry direct when gateway fallback applies`() {
        let step = RuntimeSessionDecisionPolicy.recoveryStreamNextStep(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: false,
            encounteredRecoverableFailure: false,
            responseId: nil
        )

        #expect(step == .retryDirectStream)
    }

    @Test func `poll when no fallback but recoverable failure`() {
        let step = RuntimeSessionDecisionPolicy.recoveryStreamNextStep(
            cloudflareGatewayEnabled: false,
            useDirectEndpoint: true,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: true,
            encounteredRecoverableFailure: true,
            responseId: "resp_abc"
        )

        #expect(step == .poll)
    }

    @Test func `none when no fallback and no poll path`() {
        let step = RuntimeSessionDecisionPolicy.recoveryStreamNextStep(
            cloudflareGatewayEnabled: false,
            useDirectEndpoint: true,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: true,
            encounteredRecoverableFailure: false,
            responseId: nil
        )

        #expect(step == .none)
    }

    // MARK: - Pending Background Cancellation

    @Test func `cancellation when background mode with response ID`() {
        let messageId = UUID()
        let cancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: true,
            responseId: "resp_cancel",
            messageId: messageId
        )

        #expect(cancellation != nil)
        #expect(cancellation?.responseId == "resp_cancel")
        #expect(cancellation?.messageId == messageId)
    }

    @Test func `no cancellation when not background mode`() {
        let cancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: false,
            responseId: "resp_123",
            messageId: UUID()
        )

        #expect(cancellation == nil)
    }

    @Test func `no cancellation when no response ID`() {
        let cancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: true,
            responseId: nil,
            messageId: UUID()
        )

        #expect(cancellation == nil)
    }

    // MARK: - Can Detach Background Response

    @Test func `can detach when all conditions met`() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: true,
            usedBackgroundMode: true,
            responseId: "resp_detach"
        )

        #expect(result == true)
    }

    @Test func `cannot detach when no visible session`() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: false,
            usedBackgroundMode: true,
            responseId: "resp_detach"
        )

        #expect(result == false)
    }

    @Test func `cannot detach when not background mode`() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: true,
            usedBackgroundMode: false,
            responseId: "resp_detach"
        )

        #expect(result == false)
    }

    @Test func `cannot detach when no response ID`() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: true,
            usedBackgroundMode: true,
            responseId: nil
        )

        #expect(result == false)
    }
}
