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

    func testSessionVisibilityCoordinatorOnlyReturnsLiveDraftWhenVisibleMessageExists() {
        let visibleID = UUID()
        let messages = [
            Message(id: visibleID, role: .assistant, content: "Visible"),
            Message(role: .user, content: "Prompt")
        ]

        XCTAssertEqual(
            SessionVisibilityCoordinator.liveDraftMessageID(
                visibleMessageID: visibleID,
                messages: messages
            ),
            visibleID
        )
        XCTAssertNil(
            SessionVisibilityCoordinator.liveDraftMessageID(
                visibleMessageID: UUID(),
                messages: messages
            )
        )
    }

    func testSessionVisibilityCoordinatorFlagsDetachedBubbleOnlyWhenStreamingWithoutLiveDraft() {
        XCTAssertTrue(
            SessionVisibilityCoordinator.shouldShowDetachedStreamingBubble(
                isStreaming: true,
                liveDraftMessageID: nil
            )
        )
        XCTAssertFalse(
            SessionVisibilityCoordinator.shouldShowDetachedStreamingBubble(
                isStreaming: false,
                liveDraftMessageID: nil
            )
        )
        XCTAssertFalse(
            SessionVisibilityCoordinator.shouldShowDetachedStreamingBubble(
                isStreaming: true,
                liveDraftMessageID: UUID()
            )
        )
    }

    @MainActor
    func testChatSessionRegistryCancelsSupersededSessionAndTracksVisibleSession() {
        let registry = ChatSessionRegistry()
        let conversation = Conversation()
        let message = Message(role: .assistant, content: "")
        message.conversation = conversation
        let replacement = Message(id: message.id, role: .assistant, content: "")
        replacement.conversation = conversation

        let originalSession = ResponseSession(
            message: message,
            conversationID: conversation.id,
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )
        let replacementSession = ResponseSession(
            message: replacement,
            conversationID: conversation.id,
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )

        var cancelledSessionIDs: [UUID] = []

        registry.register(originalSession, visible: true) { cancelled in
            cancelledSessionIDs.append(cancelled.messageID)
        }
        registry.register(replacementSession, visible: true) { cancelled in
            cancelledSessionIDs.append(cancelled.messageID)
        }

        XCTAssertEqual(cancelledSessionIDs, [originalSession.messageID])
        XCTAssertTrue(registry.contains(replacementSession))
        XCTAssertFalse(registry.contains(originalSession))
        XCTAssertEqual(registry.visibleMessageID, replacementSession.messageID)
        XCTAssertTrue(registry.currentVisibleSession === replacementSession)
    }

    @MainActor
    func testStreamingTransitionReducerUpdatesSequenceAndAvoidsDuplicateTransientState() {
        let conversation = Conversation()
        let message = Message(role: .assistant, content: "")
        message.conversation = conversation
        let session = ResponseSession(
            message: message,
            conversationID: conversation.id,
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )
        let citation = URLCitation(
            url: "https://example.com",
            title: "Example",
            startIndex: 0,
            endIndex: 7
        )
        let annotation = FilePathAnnotation(
            fileId: "file_123",
            containerId: nil,
            sandboxPath: "/mnt/data/example.pdf",
            filename: "example.pdf",
            startIndex: 0,
            endIndex: 7
        )

        StreamingTransitionReducer.recordSequenceUpdate(4, for: session)
        StreamingTransitionReducer.recordSequenceUpdate(2, for: session)
        StreamingTransitionReducer.recordSequenceUpdate(8, for: session)
        XCTAssertEqual(session.lastSequenceNumber, 8)

        XCTAssertTrue(StreamingTransitionReducer.addCitationIfNeeded(in: session, citation: citation))
        XCTAssertFalse(StreamingTransitionReducer.addCitationIfNeeded(in: session, citation: citation))
        XCTAssertTrue(StreamingTransitionReducer.addFilePathAnnotationIfNeeded(in: session, annotation: annotation))
        XCTAssertFalse(StreamingTransitionReducer.addFilePathAnnotationIfNeeded(in: session, annotation: annotation))
        XCTAssertEqual(session.citations.count, 1)
        XCTAssertEqual(session.filePathAnnotations.count, 1)
    }
}
