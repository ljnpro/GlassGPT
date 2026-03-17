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
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )
        let replacementSession = ResponseSession(
            message: replacement,
            conversationID: conversation.id,
            service: OpenAIService(),
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
            service: OpenAIService(),
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

    @MainActor
    func testResponseSessionCopiesRuntimeStateFromMessageMetadata() {
        let conversation = Conversation()
        let source = Message(
            role: .assistant,
            content: "seed",
            responseId: "resp_init",
            lastSequenceNumber: 17,
            usedBackgroundMode: true
        )
        let session = ResponseSession(
            message: source,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )

        XCTAssertEqual(session.runtimeState.responseId, "resp_init")
        XCTAssertEqual(session.runtimeState.lastSequenceNumber, 17)
        XCTAssertTrue(session.runtimeState.backgroundResumable)
        XCTAssertEqual(session.runtimeState.phase, .idle)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .idle)
        XCTAssertFalse(session.runtimeState.isStreaming)
        XCTAssertFalse(session.runtimeState.isRecovering)
    }

    @MainActor
    func testResponseSessionLifecycleMethodsUpdateRuntimeStateAsExpected() {
        let conversation = Conversation()
        let source = Message(role: .assistant, content: "seed", conversation: conversation)
        let session = ResponseSession(
            message: source,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )

        session.beginSubmitting()
        XCTAssertEqual(session.runtimeState.phase, .submitting)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .idle)
        XCTAssertFalse(session.runtimeState.isStreaming)

        let streamID = UUID()
        session.beginStreaming(streamID: streamID)
        XCTAssertEqual(session.runtimeState.phase, .streaming)
        XCTAssertEqual(session.runtimeState.activeStreamID, streamID)
        XCTAssertTrue(session.runtimeState.isStreaming)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .idle)
        XCTAssertFalse(session.runtimeState.isRecovering)

        session.beginRecoveryCheck(responseId: "resp_recover")
        XCTAssertEqual(session.runtimeState.phase, .recoveringStatus)
        XCTAssertEqual(session.runtimeState.responseId, "resp_recover")
        XCTAssertEqual(session.runtimeState.recoveryPhase, .checkingStatus)
        XCTAssertTrue(session.runtimeState.isRecovering)

        session.beginRecoveryStream(streamID: UUID())
        XCTAssertEqual(session.runtimeState.phase, .recoveringStream)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .streamResuming)
        XCTAssertTrue(session.runtimeState.isStreaming)
        XCTAssertTrue(session.runtimeState.isRecovering)

        session.beginRecoveryPoll()
        XCTAssertEqual(session.runtimeState.phase, .recoveringPoll)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .pollingTerminal)

        session.setRecoveryPhase(.idle)
        XCTAssertEqual(session.runtimeState.phase, .idle)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .idle)
        XCTAssertFalse(session.runtimeState.isRecovering)

        session.lastSequenceNumber = 5
        session.markCompleted()
        XCTAssertEqual(session.runtimeState.phase, .completed)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .idle)
        XCTAssertFalse(session.runtimeState.isRecovering)
        XCTAssertNil(session.runtimeState.lastSequenceNumber)
    }

    @MainActor
    func testCancelAndRecoveryPhaseTransitionsPreserveInvariantMapping() {
        let conversation = Conversation()
        let source = Message(role: .assistant, content: "seed", conversation: conversation)
        let session = ResponseSession(
            message: source,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )

        let streamID = UUID()
        session.beginStreaming(streamID: streamID)
        session.isThinking = true

        session.cancelStreaming()

        XCTAssertEqual(session.runtimeState.phase, .idle)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .idle)
        XCTAssertEqual(session.runtimeState.isThinking, false)
        XCTAssertNotEqual(session.runtimeState.activeStreamID, streamID)

        session.setRecoveryPhase(.checkingStatus)
        XCTAssertEqual(session.runtimeState.phase, .recoveringStatus)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .checkingStatus)

        session.setRecoveryPhase(.streamResuming)
        XCTAssertEqual(session.runtimeState.phase, .recoveringStream)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .streamResuming)

        session.setRecoveryPhase(.pollingTerminal)
        XCTAssertEqual(session.runtimeState.phase, .recoveringPoll)
        XCTAssertEqual(session.runtimeState.recoveryPhase, .pollingTerminal)
    }

    @MainActor
    func testSaveDraftStateStoresStreamingPayloadAndMetadata() {
        let conversation = Conversation()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        conversation.updatedAt = oldDate

        let source = Message(
            role: .assistant,
            content: "seed",
            thinking: "seed-thought",
            conversation: conversation,
            lastSequenceNumber: 7,
            isComplete: true
        )

        let session = ResponseSession(
            message: source,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )
        session.currentText = "streaming text"
        session.currentThinking = "streaming reasoning"
        session.toolCalls = [
            ToolCallInfo(
                id: "tc-1",
                type: .webSearch,
                status: .inProgress,
                code: nil,
                results: nil,
                queries: ["glassgpt"]
            )
        ]
        session.citations = [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            )
        ]
        session.filePathAnnotations = [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: nil,
                sandboxPath: "sandbox:/mnt/data/out.txt",
                filename: "out.txt",
                startIndex: 0,
                endIndex: 20
            )
        ]
        session.lastSequenceNumber = 11
        session.responseId = "resp_save"

        MessagePersistenceAdapter().saveDraftState(from: session, to: source)

        XCTAssertEqual(source.content, "streaming text")
        XCTAssertEqual(source.thinking, "streaming reasoning")
        XCTAssertEqual(source.toolCalls, session.toolCalls)
        XCTAssertEqual(source.annotations, session.citations)
        XCTAssertEqual(source.filePathAnnotations, session.filePathAnnotations)
        XCTAssertEqual(source.lastSequenceNumber, 11)
        XCTAssertEqual(source.responseId, "resp_save")
        XCTAssertTrue(source.usedBackgroundMode)
        XCTAssertFalse(source.isComplete)
        XCTAssertGreaterThan(source.conversation?.updatedAt ?? .distantPast, oldDate)
    }

    @MainActor
    func testFinalizeCompletedSessionMarksCompleteAndClearsStreamingMetadata() {
        let conversation = Conversation()
        let source = Message(
            role: .assistant,
            content: "seed",
            conversation: conversation,
            responseId: "resp_old",
            lastSequenceNumber: 99,
            isComplete: false
        )

        let session = ResponseSession(
            message: source,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: false,
            requestServiceTier: .standard
        )
        session.currentText = "final text"
        session.currentThinking = ""
        session.toolCalls = [
            ToolCallInfo(
                id: "tc-2",
                type: .codeInterpreter,
                status: .completed,
                code: "print(2)",
                results: ["2"],
                queries: nil
            )
        ]
        session.responseId = "resp_complete"
        session.lastSequenceNumber = 12

        MessagePersistenceAdapter().finalizeCompletedSession(from: session, to: source)

        XCTAssertEqual(source.content, "final text")
        XCTAssertNil(source.thinking)
        XCTAssertEqual(source.toolCalls, session.toolCalls)
        XCTAssertEqual(source.responseId, "resp_complete")
        XCTAssertNil(source.lastSequenceNumber)
        XCTAssertTrue(source.isComplete)
    }

    @MainActor
    func testFinalizePartialSessionFallsBackToExistingTextAndInterruptionMessageWhenMissing() {
        let conversation = Conversation()
        let source = Message(
            role: .assistant,
            content: "",
            thinking: "existing thinking",
            conversation: conversation,
            isComplete: false
        )

        let session = ResponseSession(
            message: source,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: false,
            requestServiceTier: .standard
        )
        session.currentText = ""
        session.currentThinking = ""
        session.citations = [
            URLCitation(
                url: "https://partial.example.com",
                title: "Partial",
                startIndex: 0,
                endIndex: 7
            )
        ]
        session.responseId = "resp_partial"
        session.lastSequenceNumber = 3

        MessagePersistenceAdapter().finalizePartialSession(from: session, to: source)

        XCTAssertEqual(
            source.content,
            "[Response interrupted. Please try again.]"
        )
        XCTAssertEqual(source.thinking, "existing thinking")
        XCTAssertEqual(source.annotations, session.citations)
        XCTAssertNil(source.lastSequenceNumber)
        XCTAssertEqual(source.responseId, "resp_partial")
        XCTAssertTrue(source.isComplete)
    }

    @MainActor
    func testRefreshFileAnnotationsReplacesStoredFilePathAnnotations() {
        let conversation = Conversation()
        let source = Message(
            role: .assistant,
            content: "seed",
            conversation: conversation,
            filePathAnnotations: [
                FilePathAnnotation(
                    fileId: "old",
                    containerId: nil,
                    sandboxPath: "old",
                    filename: "old.txt",
                    startIndex: 0,
                    endIndex: 3
                )
            ]
        )

        let replacement = [
            FilePathAnnotation(
                fileId: "new",
                containerId: "container",
                sandboxPath: "sandbox:/mnt/data/new.txt",
                filename: "new.txt",
                startIndex: 0,
                endIndex: 20
            )
        ]

        MessagePersistenceAdapter().refreshFileAnnotations(replacement, on: source)

        XCTAssertEqual(source.filePathAnnotations, replacement)
    }
}
