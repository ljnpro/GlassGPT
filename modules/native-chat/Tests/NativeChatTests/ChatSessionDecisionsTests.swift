import ChatRuntimeModel
import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport
import XCTest
@testable import NativeChatComposition

final class ChatSessionDecisionsTests: XCTestCase {
    func testRecoveryResumeModeUsesStreamingWhenBackgroundModeAndSequenceExist() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        XCTAssertEqual(mode, .stream(lastSequenceNumber: 42))
    }

    func testRecoveryResumeModeFallsBackToPollingWhenBackgroundModeIsDisabled() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 42
        )

        XCTAssertEqual(mode, .poll)
    }

    func testRecoveryResumeModeFallsBackToPollingWhenStreamingResumeIsNotPreferred() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: false,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        XCTAssertEqual(mode, .poll)
    }

    func testGatewayFallbackTriggersDirectResumeWhenNoRecoveryEventsArrive() {
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
    }

    func testGatewayFallbackDoesNotTriggerAfterRecoveryEventsOnDirectRoute() {
        XCTAssertFalse(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: true,
                gatewayResumeTimedOut: true,
                receivedAnyRecoveryEvent: false
            )
        )
    }

    func testGatewayFallbackTriggersWhenGatewayResumeTimesOut() {
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: true,
                receivedAnyRecoveryEvent: true
            )
        )
    }

    func testPollAfterRecoveryStreamWhenRecoverableFailureOccursOrResponseStillTracked() {
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: true,
                responseId: nil
            )
        )
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: "resp_123"
            )
        )
        XCTAssertFalse(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: nil
            )
        )
    }

    func testBackgroundCancellationAndDetachOnlyApplyToBackgroundResponses() {
        let messageId = UUID()

        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_123",
                messageId: messageId
            ),
            RuntimePendingBackgroundCancellation(responseId: "resp_123", messageId: messageId)
        )
        XCTAssertNil(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: false,
                responseId: "resp_123",
                messageId: messageId
            )
        )

        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
        XCTAssertFalse(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
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

        let originalSession = ReplySession(
            message: message,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: true,
            requestServiceTier: .standard
        )
        let replacementSession = ReplySession(
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
        let session = ReplySession(
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
    func testStreamingTransitionReducerTracksThinkingTextAndToolCode() {
        let session = makeResponseSession()

        XCTAssertFalse(StreamingTransitionReducer.applyTextDelta("Hello", to: session))
        XCTAssertEqual(session.currentText, "Hello")

        XCTAssertTrue(StreamingTransitionReducer.setThinking(true, for: session))
        XCTAssertTrue(StreamingTransitionReducer.applyTextDelta(" world", to: session))
        XCTAssertEqual(session.currentText, "Hello world")
        XCTAssertEqual(session.currentThinking, "")

        StreamingTransitionReducer.applyThinkingDelta("plan", to: session)
        XCTAssertEqual(session.currentThinking, "plan")
        XCTAssertFalse(StreamingTransitionReducer.setThinking(true, for: session))
        XCTAssertTrue(StreamingTransitionReducer.setThinking(false, for: session))

        XCTAssertTrue(
            StreamingTransitionReducer.startToolCallIfNeeded(
                in: session,
                id: "tool_1",
                type: .codeInterpreter
            )
        )
        XCTAssertTrue(
            StreamingTransitionReducer.appendToolCodeDelta(
                in: session,
                id: "tool_1",
                delta: "print("
            )
        )
        XCTAssertTrue(
            StreamingTransitionReducer.appendToolCodeDelta(
                in: session,
                id: "tool_1",
                delta: "\"ok\")"
            )
        )
        XCTAssertEqual(session.toolCalls.first?.code, "print(\"ok\")")
        XCTAssertTrue(
            StreamingTransitionReducer.setToolCode(
                in: session,
                id: "tool_1",
                code: "print(\"final\")"
            )
        )
        XCTAssertEqual(session.toolCalls.first?.code, "print(\"final\")")
        XCTAssertTrue(
            StreamingTransitionReducer.setToolCallStatus(
                in: session,
                id: "tool_1",
                status: .completed
            )
        )
        XCTAssertEqual(session.toolCalls.first?.status, .completed)
        XCTAssertFalse(
            StreamingTransitionReducer.setToolCode(
                in: session,
                id: "missing",
                code: "noop"
            )
        )
        XCTAssertFalse(
            StreamingTransitionReducer.appendToolCodeDelta(
                in: session,
                id: "missing",
                delta: "noop"
            )
        )
        XCTAssertFalse(
            StreamingTransitionReducer.setToolCallStatus(
                in: session,
                id: "missing",
                status: .completed
            )
        )
    }

    @MainActor
    func testStreamingTransitionReducerMergeTerminalPayloadKeepsExistingValuesWhenIncomingValuesAreEmpty() {
        let session = makeResponseSession()
        session.currentText = "existing text"
        session.currentThinking = "existing thinking"
        session.filePathAnnotations = [
            FilePathAnnotation(
                fileId: "existing-file",
                containerId: nil,
                sandboxPath: "sandbox:/mnt/data/existing.txt",
                filename: "existing.txt",
                startIndex: 0,
                endIndex: 10
            )
        ]

        StreamingTransitionReducer.mergeTerminalPayload(
            text: "",
            thinking: "",
            filePathAnnotations: [],
            into: session
        )

        XCTAssertEqual(session.currentText, "existing text")
        XCTAssertEqual(session.currentThinking, "existing thinking")
        XCTAssertEqual(session.filePathAnnotations.count, 1)

        let replacement = [
            FilePathAnnotation(
                fileId: "replacement-file",
                containerId: "container_1",
                sandboxPath: "sandbox:/mnt/data/replacement.txt",
                filename: "replacement.txt",
                startIndex: 1,
                endIndex: 11
            )
        ]

        StreamingTransitionReducer.mergeTerminalPayload(
            text: "final text",
            thinking: "final thinking",
            filePathAnnotations: replacement,
            into: session
        )

        XCTAssertEqual(session.currentText, "final text")
        XCTAssertEqual(session.currentThinking, "final thinking")
        XCTAssertEqual(session.filePathAnnotations, replacement)
    }

    @MainActor
    func testSessionVisibilityCoordinatorVisibleAndClearedStateMirrorSessionRuntime() {
        let conversation = Conversation()
        let draft = Message(role: .assistant, content: "draft", conversation: conversation)
        let session = ReplySession(
            message: draft,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4_pro,
            requestEffort: .xhigh,
            requestUsesBackgroundMode: true,
            requestServiceTier: .flex
        )
        session.currentText = "visible text"
        session.currentThinking = "visible thinking"
        session.toolCalls = [
            ToolCallInfo(
                id: "tool_1",
                type: .webSearch,
                status: .searching,
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
                fileId: "file_123",
                containerId: nil,
                sandboxPath: "sandbox:/mnt/data/file.txt",
                filename: "file.txt",
                startIndex: 0,
                endIndex: 8
            )
        ]
        session.lastSequenceNumber = 42
        session.beginRecoveryStream(streamID: UUID())
        session.isThinking = true

        let visibleState = SessionVisibilityCoordinator.visibleState(from: session, draftMessage: draft)

        XCTAssertEqual(visibleState.draftMessage?.id, draft.id)
        XCTAssertEqual(visibleState.currentStreamingText, "visible text")
        XCTAssertEqual(visibleState.currentThinkingText, "visible thinking")
        XCTAssertEqual(visibleState.activeToolCalls, session.toolCalls)
        XCTAssertEqual(visibleState.liveCitations, session.citations)
        XCTAssertEqual(visibleState.liveFilePathAnnotations, session.filePathAnnotations)
        XCTAssertEqual(visibleState.lastSequenceNumber, 42)
        XCTAssertEqual(visibleState.activeRequestModel, .gpt5_4_pro)
        XCTAssertEqual(visibleState.activeRequestEffort, .xhigh)
        XCTAssertTrue(visibleState.activeRequestUsesBackgroundMode)
        XCTAssertEqual(visibleState.activeRequestServiceTier, .flex)
        XCTAssertTrue(visibleState.isStreaming)
        XCTAssertTrue(visibleState.isRecovering)
        XCTAssertEqual(visibleState.visibleRecoveryPhase, .streamResuming)
        XCTAssertTrue(visibleState.isThinking)

        let retained = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: false)
        XCTAssertEqual(retained.draftMessage?.id, draft.id)
        XCTAssertFalse(retained.isStreaming)
        XCTAssertFalse(retained.isRecovering)
        XCTAssertEqual(retained.visibleRecoveryPhase, .idle)
        XCTAssertEqual(retained.activeToolCalls, [])

        let cleared = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: true)
        XCTAssertNil(cleared.draftMessage)
        XCTAssertEqual(cleared.currentStreamingText, "")
        XCTAssertEqual(cleared.currentThinkingText, "")
        XCTAssertEqual(cleared.activeRequestModel, nil)
    }

    @MainActor
    func testChatSessionRegistryRemoveAllAndActiveMessageSelectionPreferRegisteredSessions() {
        let registry = ChatSessionRegistry()
        let conversation = Conversation()
        let olderDraft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        olderDraft.createdAt = Date(timeIntervalSince1970: 1)
        let newerDraft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        newerDraft.createdAt = Date(timeIntervalSince1970: 2)
        let completed = Message(role: .assistant, content: "done", conversation: conversation, isComplete: true)
        conversation.messages = [olderDraft, newerDraft, completed]

        let olderSession = ReplySession(
            message: olderDraft,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: false,
            requestServiceTier: .standard
        )
        let newerSession = ReplySession(
            message: newerDraft,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: .gpt5_4,
            requestEffort: .high,
            requestUsesBackgroundMode: false,
            requestServiceTier: .standard
        )

        registry.register(olderSession, visible: false) { _ in }
        registry.register(newerSession, visible: true) { _ in }

        XCTAssertTrue(registry.hasVisibleSession(in: conversation.id))
        XCTAssertEqual(
            registry.activeMessageID(
                in: conversation,
                fallbackMessages: [completed, olderDraft, newerDraft]
            ),
            newerDraft.id
        )

        var cancelled: [UUID] = []
        registry.remove(olderSession) { _ in cancelled.append(olderSession.messageID) }
        XCTAssertEqual(cancelled, [olderSession.messageID])
        XCTAssertNil(registry.session(for: olderDraft.id))

        registry.removeAll { _ in cancelled.append(newerSession.messageID) }
        XCTAssertNil(registry.visibleMessageID)
        XCTAssertFalse(registry.hasVisibleSession(in: conversation.id))
        XCTAssertNil(
            registry.activeMessageID(
                in: conversation,
                fallbackMessages: [completed, olderDraft, newerDraft]
            )
        )
        XCTAssertEqual(Set(cancelled), Set([olderSession.messageID, newerSession.messageID]))
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
        let session = ReplySession(
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
        let session = ReplySession(
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
        let session = ReplySession(
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

        let session = ReplySession(
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

        ChatPersistenceSwiftData.MessagePersistenceAdapter().saveDraftState(from: session, to: source)

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

        let session = ReplySession(
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

        ChatPersistenceSwiftData.MessagePersistenceAdapter().finalizeCompletedSession(from: session, to: source)

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

        let session = ReplySession(
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

        ChatPersistenceSwiftData.MessagePersistenceAdapter().finalizePartialSession(from: session, to: source)

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

        ChatPersistenceSwiftData.MessagePersistenceAdapter().refreshFileAnnotations(replacement, on: source)

        XCTAssertEqual(source.filePathAnnotations, replacement)
    }

    @MainActor
    func testApplyRecoveredResultUsesFetchedPayloadAndFallsBackWhenNeeded() {
        let conversation = Conversation()
        let message = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            isComplete: false
        )

        let result = OpenAIResponseFetchResult(
            status: .completed,
            text: "",
            thinking: nil,
            annotations: [
                URLCitation(
                    url: "https://example.com/recovered",
                    title: "Recovered",
                    startIndex: 0,
                    endIndex: 9
                )
            ],
            toolCalls: [
                ToolCallInfo(
                    id: "tool_1",
                    type: .codeInterpreter,
                    status: .completed,
                    code: "print(1)",
                    results: ["1"],
                    queries: nil
                )
            ],
            filePathAnnotations: [
                FilePathAnnotation(
                    fileId: "file_recovered",
                    containerId: "container_1",
                    sandboxPath: "sandbox:/mnt/data/recovered.txt",
                    filename: "recovered.txt",
                    startIndex: 0,
                    endIndex: 12
                )
            ],
            errorMessage: nil
        )

        ChatPersistenceSwiftData.MessagePersistenceAdapter().applyRecoveredResult(
            result,
            to: message,
            fallbackText: "fallback text",
            fallbackThinking: "fallback thinking"
        )

        XCTAssertEqual(message.content, "fallback text")
        XCTAssertEqual(message.thinking, "fallback thinking")
        XCTAssertEqual(message.annotations, result.annotations)
        XCTAssertEqual(message.toolCalls, result.toolCalls)
        XCTAssertEqual(message.filePathAnnotations, result.filePathAnnotations)
        XCTAssertTrue(message.isComplete)
        XCTAssertNil(message.lastSequenceNumber)
    }

    @MainActor
    func testSetFileAttachmentsStoresPayloadOnMessage() {
        let message = Message(role: .assistant, content: "seed")
        let attachments = [
            FileAttachment(
                filename: "report.pdf",
                fileSize: 1024,
                fileType: "application/pdf",
                fileId: "file_123",
                localData: nil,
                uploadStatus: .uploaded
            )
        ]

        ChatPersistenceSwiftData.MessagePersistenceAdapter().setFileAttachments(attachments, on: message)

        XCTAssertEqual(message.fileAttachments.count, 1)
        XCTAssertEqual(message.fileAttachments.first?.filename, "report.pdf")
        XCTAssertEqual(message.fileAttachments.first?.fileId, "file_123")
        XCTAssertEqual(message.fileAttachments.first?.uploadStatus.rawValue, FileUploadStatus.uploaded.rawValue)
    }

    @MainActor
    private func makeResponseSession(
        model: ModelType = .gpt5_4,
        effort: ReasoningEffort = .high,
        usesBackgroundMode: Bool = true,
        serviceTier: ServiceTier = .standard
    ) -> ReplySession {
        let conversation = Conversation()
        let message = Message(role: .assistant, content: "", conversation: conversation)
        return ReplySession(
            message: message,
            conversationID: conversation.id,
            service: OpenAIService(),
            requestModel: model,
            requestEffort: effort,
            requestUsesBackgroundMode: usesBackgroundMode,
            requestServiceTier: serviceTier
        )
    }
}

@MainActor
private extension ReplySession {
    convenience init(
        message: Message,
        conversationID: UUID,
        service _: OpenAIService,
        requestModel: ModelType,
        requestEffort: ReasoningEffort,
        requestUsesBackgroundMode: Bool,
        requestServiceTier: ServiceTier
    ) {
        self.init(
            message: message,
            conversationID: conversationID,
            request: ResponseRequestContext(
                apiKey: "sk-test",
                messages: nil,
                model: requestModel,
                effort: requestEffort,
                usesBackgroundMode: requestUsesBackgroundMode,
                serviceTier: requestServiceTier
            )
        )
    }
}

@MainActor
private extension ChatSessionRegistry {
    func register(
        _ session: ReplySession,
        visible: Bool,
        cancelExisting: (ReplySession) -> Void
    ) {
        let existingSession = self.session(for: session.messageID)
        register(
            session,
            execution: SessionExecutionState(service: OpenAIService()),
            visible: visible
        ) { _ in
            if let existingSession, existingSession !== session {
                cancelExisting(existingSession)
            }
        }
    }
}

@MainActor
private extension ChatPersistenceSwiftData.MessagePersistenceAdapter {
    func saveDraftState(from session: ReplySession, to message: Message) {
        saveDraftState(from: snapshot(of: session), to: message)
    }

    func finalizeCompletedSession(from session: ReplySession, to message: Message) {
        finalizeCompletedSession(from: snapshot(of: session), to: message)
    }

    func finalizePartialSession(from session: ReplySession, to message: Message) {
        finalizePartialSession(from: snapshot(of: session), to: message)
    }

    private func snapshot(of session: ReplySession) -> ReplySessionSnapshot {
        ReplySessionSnapshot(
            currentText: session.currentText,
            currentThinking: session.currentThinking,
            toolCalls: session.toolCalls,
            citations: session.citations,
            filePathAnnotations: session.filePathAnnotations,
            lastSequenceNumber: session.lastSequenceNumber,
            responseId: session.responseId,
            requestUsesBackgroundMode: session.request.usesBackgroundMode
        )
    }
}
