import XCTest
@testable import NativeChat

final class ChatSessionDecisionsTests: XCTestCase {
    func testRecoveryResumeModeUsesStreamingWhenBackgroundModeAndSequenceExist() {
        let mode = ChatSessionDecisions.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        XCTAssertEqual(mode, .stream(lastSequenceNumber: 42))
    }

    func testRecoveryResumeModeFallsBackToPollingWhenBackgroundModeIsDisabled() {
        let mode = ChatSessionDecisions.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 42
        )

        XCTAssertEqual(mode, .poll)
    }

    func testRecoveryResumeModeFallsBackToPollingWhenStreamingResumeIsNotPreferred() {
        let mode = ChatSessionDecisions.recoveryResumeMode(
            preferStreamingResume: false,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        XCTAssertEqual(mode, .poll)
    }

    func testGatewayFallbackTriggersDirectResumeWhenNoRecoveryEventsArrive() {
        XCTAssertTrue(
            ChatSessionDecisions.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
    }

    func testGatewayFallbackDoesNotTriggerAfterRecoveryEventsOnDirectRoute() {
        XCTAssertFalse(
            ChatSessionDecisions.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: true,
                gatewayResumeTimedOut: true,
                receivedAnyRecoveryEvent: false
            )
        )
    }

    func testGatewayFallbackTriggersWhenGatewayResumeTimesOut() {
        XCTAssertTrue(
            ChatSessionDecisions.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: true,
                receivedAnyRecoveryEvent: true
            )
        )
    }

    func testPollAfterRecoveryStreamWhenRecoverableFailureOccursOrResponseStillTracked() {
        XCTAssertTrue(
            ChatSessionDecisions.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: true,
                responseId: nil
            )
        )
        XCTAssertTrue(
            ChatSessionDecisions.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: "resp_123"
            )
        )
        XCTAssertFalse(
            ChatSessionDecisions.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: nil
            )
        )
    }

    func testBackgroundCancellationAndDetachOnlyApplyToBackgroundResponses() {
        let messageId = UUID()

        XCTAssertEqual(
            ChatSessionDecisions.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_123",
                messageId: messageId
            ),
            PendingBackgroundCancellation(responseId: "resp_123", messageId: messageId)
        )
        XCTAssertNil(
            ChatSessionDecisions.pendingBackgroundCancellation(
                requestUsesBackgroundMode: false,
                responseId: "resp_123",
                messageId: messageId
            )
        )

        XCTAssertTrue(
            ChatSessionDecisions.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
        XCTAssertFalse(
            ChatSessionDecisions.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: false,
                responseId: "resp_123"
            )
        )
    }
}
