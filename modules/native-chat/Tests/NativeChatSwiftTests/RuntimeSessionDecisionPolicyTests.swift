import ChatRuntimeModel
import Foundation
import Testing

/// Comprehensive tests for ``RuntimeSessionDecisionPolicy``.
struct RuntimeSessionDecisionPolicyTests {

    // MARK: - Recovery Resume Mode

    @Test func streamResumeWhenAllConditionsMet() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        #expect(mode == .stream(lastSequenceNumber: 42))
    }

    @Test func pollWhenNotPreferringStreamResume() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: false,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        #expect(mode == .poll)
    }

    @Test func pollWhenNotUsingBackgroundMode() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 42
        )

        #expect(mode == .poll)
    }

    @Test func pollWhenNoLastSequenceNumber() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: nil
        )

        #expect(mode == .poll)
    }

    // MARK: - Recovery Fetch Action

    @Test func finishCompletedForCompletedStatus() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .completed,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: nil
        )

        #expect(action == .finish(.completed))
    }

    @Test func finishFailedWithErrorMessage() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .failed,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: "Rate limit"
        )

        #expect(action == .finish(.failed("Rate limit")))
    }

    @Test func finishFailedWithNilErrorMessage() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .failed,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: nil
        )

        #expect(action == .finish(.failed(nil)))
    }

    @Test func startStreamForInProgressWithAllResumeConditions() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .inProgress,
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 17,
            errorMessage: nil
        )

        #expect(action == .startStream(lastSequenceNumber: 17))
    }

    @Test func pollForQueuedWithoutResumeConditions() {
        let action = RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: .queued,
            preferStreamingResume: false,
            usedBackgroundMode: false,
            lastSequenceNumber: nil,
            errorMessage: nil
        )

        #expect(action == .poll)
    }

    @Test func pollForInProgressWithoutBackgroundMode() {
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

    @Test func fallbackWhenGatewayTimedOut() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: true
        )

        #expect(result == true)
    }

    @Test func fallbackWhenNoEventsReceived() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: false
        )

        #expect(result == true)
    }

    @Test func noFallbackWhenAlreadyDirect() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: true,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: false
        )

        #expect(result == false)
    }

    @Test func noFallbackWhenGatewayDisabled() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: false,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: true,
            receivedAnyRecoveryEvent: false
        )

        #expect(result == false)
    }

    @Test func noFallbackWhenEventsReceivedAndNoTimeout() {
        let result = RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: true,
            useDirectEndpoint: false,
            gatewayResumeTimedOut: false,
            receivedAnyRecoveryEvent: true
        )

        #expect(result == false)
    }

    // MARK: - Should Poll After Recovery Stream

    @Test func pollWhenRecoverableFailure() {
        let result = RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: true,
            responseId: nil
        )

        #expect(result == true)
    }

    @Test func pollWhenResponseIDPresent() {
        let result = RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: false,
            responseId: "resp_123"
        )

        #expect(result == true)
    }

    @Test func noPollWhenNoFailureAndNoResponseID() {
        let result = RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: false,
            responseId: nil
        )

        #expect(result == false)
    }

    // MARK: - Recovery Stream Next Step

    @Test func retryDirectWhenGatewayFallbackApplies() {
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

    @Test func pollWhenNoFallbackButRecoverableFailure() {
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

    @Test func noneWhenNoFallbackAndNoPollPath() {
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

    @Test func cancellationWhenBackgroundModeWithResponseID() {
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

    @Test func noCancellationWhenNotBackgroundMode() {
        let cancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: false,
            responseId: "resp_123",
            messageId: UUID()
        )

        #expect(cancellation == nil)
    }

    @Test func noCancellationWhenNoResponseID() {
        let cancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: true,
            responseId: nil,
            messageId: UUID()
        )

        #expect(cancellation == nil)
    }

    // MARK: - Can Detach Background Response

    @Test func canDetachWhenAllConditionsMet() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: true,
            usedBackgroundMode: true,
            responseId: "resp_detach"
        )

        #expect(result == true)
    }

    @Test func cannotDetachWhenNoVisibleSession() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: false,
            usedBackgroundMode: true,
            responseId: "resp_detach"
        )

        #expect(result == false)
    }

    @Test func cannotDetachWhenNotBackgroundMode() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: true,
            usedBackgroundMode: false,
            responseId: "resp_detach"
        )

        #expect(result == false)
    }

    @Test func cannotDetachWhenNoResponseID() {
        let result = RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
            hasVisibleSession: true,
            usedBackgroundMode: true,
            responseId: nil
        )

        #expect(result == false)
    }
}
