import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import OpenAITransport
import XCTest
@testable import NativeChatComposition

@MainActor
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

    func testPendingBackgroundCancellationAndDetachOnlyApplyToBackgroundResponses() {
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
                hasVisibleSession: false,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
    }

    func testReplySessionActorOwnsLifecycleCursorAndThinkingState() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        var snapshot = await actor.apply(.beginSubmitting)
        XCTAssertEqual(snapshot.lifecycle, .preparingInput)
        XCTAssertFalse(snapshot.isThinking)

        snapshot = await actor.apply(.beginStreaming(streamID: UUID(), route: .gateway))
        XCTAssertEqual(snapshot.lifecycle, .preparingInput)

        snapshot = await actor.apply(.recordResponseCreated("resp_stream", route: .gateway))
        guard case .streaming(let cursor) = snapshot.lifecycle else {
            return XCTFail("Expected streaming lifecycle after response creation")
        }
        XCTAssertEqual(cursor.responseID, "resp_stream")
        XCTAssertNil(cursor.lastSequenceNumber)

        snapshot = await actor.apply(.recordSequenceUpdate(8))
        XCTAssertEqual(snapshot.lastSequenceNumber, 8)

        snapshot = await actor.apply(
            .beginRecoveryStatus(
                responseID: "resp_stream",
                lastSequenceNumber: 8,
                usedBackgroundMode: true,
                route: .gateway
            )
        )
        guard case .recoveringStatus(let ticket) = snapshot.lifecycle else {
            return XCTFail("Expected recoveringStatus lifecycle")
        }
        XCTAssertEqual(ticket.responseID, "resp_stream")
        XCTAssertEqual(ticket.lastSequenceNumber, 8)
        XCTAssertTrue(snapshot.isRecovering)

        snapshot = await actor.apply(.beginRecoveryStream(streamID: UUID()))
        guard case .recoveringStream(let recoveryCursor) = snapshot.lifecycle else {
            return XCTFail("Expected recoveringStream lifecycle")
        }
        XCTAssertEqual(recoveryCursor.responseID, "resp_stream")
        XCTAssertTrue(snapshot.isStreaming)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case .recoveringPoll(let pollTicket) = snapshot.lifecycle else {
            return XCTFail("Expected recoveringPoll lifecycle")
        }
        XCTAssertEqual(pollTicket.responseID, "resp_stream")

        snapshot = await actor.apply(.markCompleted)
        XCTAssertEqual(snapshot.lifecycle, .completed)
        XCTAssertFalse(snapshot.isRecovering)
        XCTAssertFalse(snapshot.isThinking)
    }

    func testReplySessionActorAccumulatedBufferAndToolMutations() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.recordResponseCreated("resp_tools", route: .direct))
        _ = await actor.apply(.appendText("Hello"))
        _ = await actor.apply(.appendText(" world"))
        _ = await actor.apply(.appendThinking("Plan"))
        _ = await actor.apply(.setThinking(true))
        _ = await actor.apply(.startToolCall(id: "tool_1", type: .webSearch))
        _ = await actor.apply(.setToolCallStatus(id: "tool_1", status: .searching))
        _ = await actor.apply(.appendToolCode(id: "tool_1", delta: "print("))
        _ = await actor.apply(.appendToolCode(id: "tool_1", delta: "\"ok\")"))
        _ = await actor.apply(
            .addCitation(
                URLCitation(
                    url: "https://example.com",
                    title: "Example",
                    startIndex: 0,
                    endIndex: 5
                )
            )
        )
        _ = await actor.apply(
            .addFilePathAnnotation(
                FilePathAnnotation(
                    fileId: "file_1",
                    containerId: "ctr_1",
                    sandboxPath: "sandbox:/tmp/report.txt",
                    filename: "report.txt",
                    startIndex: 0,
                    endIndex: 10
                )
            )
        )

        let snapshot = await actor.snapshot()
        XCTAssertEqual(snapshot.buffer.text, "Hello world")
        XCTAssertEqual(snapshot.buffer.thinking, "Plan")
        XCTAssertTrue(snapshot.isThinking)
        XCTAssertEqual(snapshot.buffer.toolCalls.count, 1)
        XCTAssertEqual(snapshot.buffer.toolCalls.first?.status, .searching)
        XCTAssertEqual(snapshot.buffer.toolCalls.first?.code, "print(\"ok\")")
        XCTAssertEqual(snapshot.buffer.citations.count, 1)
        XCTAssertEqual(snapshot.buffer.filePathAnnotations.count, 1)
    }

    func testReplySessionActorMergesTerminalPayloadAndSupportsCancellation() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.recordResponseCreated("resp_terminal", route: .gateway))
        _ = await actor.apply(.appendText("partial"))
        _ = await actor.apply(.appendThinking("draft"))
        _ = await actor.apply(
            .mergeTerminalPayload(
                text: "final",
                thinking: "reasoning",
                filePathAnnotations: [
                    FilePathAnnotation(
                        fileId: "file_final",
                        containerId: "ctr_final",
                        sandboxPath: "sandbox:/tmp/final.txt",
                        filename: "final.txt",
                        startIndex: 0,
                        endIndex: 9
                    )
                ]
            )
        )

        var snapshot = await actor.snapshot()
        XCTAssertEqual(snapshot.buffer.text, "final")
        XCTAssertEqual(snapshot.buffer.thinking, "reasoning")
        XCTAssertEqual(snapshot.buffer.filePathAnnotations.count, 1)

        snapshot = await actor.apply(.cancelStreaming)
        XCTAssertEqual(snapshot.lifecycle, .idle)
        XCTAssertFalse(snapshot.isThinking)
    }

    func testReplySessionActorCoversDuplicateAndNoOpBranches() async {
        let baseState = ReplyRuntimeState(
            assistantReplyID: AssistantReplyID(),
            messageID: UUID(),
            conversationID: UUID(),
            lifecycle: .streaming(
                StreamCursor(
                    responseID: "resp_branch",
                    lastSequenceNumber: 3,
                    route: .direct
                )
            )
        )
        let actor = ReplySessionActor(initialState: baseState)

        var snapshot = await actor.apply(.beginUploadingAttachments)
        XCTAssertEqual(snapshot.lifecycle, .uploadingAttachments)

        snapshot = await actor.apply(.beginStreaming(streamID: UUID(), route: .direct))
        XCTAssertEqual(snapshot.lifecycle, .preparingInput)

        let streamingActor = ReplySessionActor(initialState: baseState)
        snapshot = await streamingActor.apply(.beginStreaming(streamID: UUID(), route: .direct))
        XCTAssertEqual(
            snapshot.lifecycle,
            .streaming(StreamCursor(responseID: "resp_branch", lastSequenceNumber: 3, route: .direct))
        )

        _ = await actor.apply(.startToolCall(id: "tool_dup", type: .webSearch))
        snapshot = await actor.apply(.startToolCall(id: "tool_dup", type: .webSearch))
        XCTAssertEqual(snapshot.buffer.toolCalls.count, 1)

        snapshot = await actor.apply(.setToolCallStatus(id: "missing", status: .completed))
        XCTAssertEqual(snapshot.buffer.toolCalls.count, 1)

        snapshot = await actor.apply(.appendToolCode(id: "missing", delta: "ignored"))
        XCTAssertNil(snapshot.buffer.toolCalls.first?.code)

        snapshot = await actor.apply(.setToolCode(id: "missing", code: "ignored"))
        XCTAssertNil(snapshot.buffer.toolCalls.first?.code)

        let citation = URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)
        _ = await actor.apply(.addCitation(citation))
        snapshot = await actor.apply(.addCitation(citation))
        XCTAssertEqual(snapshot.buffer.citations.count, 1)

        let annotation = FilePathAnnotation(
            fileId: "file_dup",
            containerId: "ctr_dup",
            sandboxPath: "sandbox:/tmp/dup.txt",
            filename: "dup.txt",
            startIndex: 0,
            endIndex: 7
        )
        _ = await actor.apply(.addFilePathAnnotation(annotation))
        snapshot = await actor.apply(.addFilePathAnnotation(annotation))
        XCTAssertEqual(snapshot.buffer.filePathAnnotations.count, 1)

        snapshot = await actor.apply(.mergeTerminalPayload(text: "", thinking: nil, filePathAnnotations: nil))
        XCTAssertEqual(snapshot.buffer.text, "")
    }

    func testReplySessionActorCoversRecoveryLifecycleBranches() async {
        let assistantReplyID = AssistantReplyID()
        let messageID = UUID()
        let conversationID = UUID()
        let ticket = DetachedRecoveryTicket(
            assistantReplyID: assistantReplyID,
            messageID: messageID,
            conversationID: conversationID,
            responseID: "resp_recover",
            lastSequenceNumber: 5,
            usedBackgroundMode: true,
            route: .gateway
        )
        let actor = ReplySessionActor(
            initialState: ReplyRuntimeState(
                assistantReplyID: assistantReplyID,
                messageID: messageID,
                conversationID: conversationID,
                lifecycle: .recoveringStatus(ticket)
            )
        )

        var snapshot = await actor.apply(.recordResponseCreated("resp_updated", route: .gateway))
        guard case .recoveringStatus(let updatedStatusTicket) = snapshot.lifecycle else {
            return XCTFail("Expected recoveringStatus ticket update")
        }
        XCTAssertEqual(updatedStatusTicket.responseID, "resp_updated")

        snapshot = await actor.apply(.recordSequenceUpdate(9))
        XCTAssertEqual(snapshot.lastSequenceNumber, 9)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case .recoveringPoll(let pollTicket) = snapshot.lifecycle else {
            return XCTFail("Expected recoveringPoll ticket")
        }
        XCTAssertTrue(pollTicket.usedBackgroundMode)
        XCTAssertEqual(pollTicket.lastSequenceNumber, 9)

        snapshot = await actor.apply(.detachForBackground(usedBackgroundMode: true))
        guard case .detached(let detachedTicket) = snapshot.lifecycle else {
            return XCTFail("Expected detached lifecycle")
        }
        XCTAssertTrue(detachedTicket.usedBackgroundMode)

        let failedActor = ReplySessionActor(initialState: makeRuntimeState())
        snapshot = await failedActor.apply(.detachForBackground(usedBackgroundMode: false))
        XCTAssertEqual(snapshot.lifecycle, .failed(nil))
    }

    func testRuntimeRegistryActorStartLookupAndRemovePaths() async {
        let registry = RuntimeRegistryActor()
        let messageID = UUID()
        let conversationID = UUID()

        let replyID = await registry.startSession(messageID: messageID, conversationID: conversationID)
        let containsReply = await registry.contains(replyID)
        let activeReplyIDs = await registry.activeReplyIDs()
        XCTAssertTrue(containsReply)
        XCTAssertEqual(activeReplyIDs, [replyID])

        let session = await registry.session(for: replyID)
        XCTAssertNotNil(session)

        await registry.remove(replyID)
        let containsReplyAfterRemove = await registry.contains(replyID)
        let activeReplyIDsAfterRemove = await registry.activeReplyIDs()
        XCTAssertFalse(containsReplyAfterRemove)
        XCTAssertTrue(activeReplyIDsAfterRemove.isEmpty)
    }

    func testReplySessionActorReplaceStateAndActiveStreamQueries() async {
        let streamID = UUID()
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.beginStreaming(streamID: streamID, route: .gateway))
        let matchesActiveStream = await actor.isActiveStream(streamID)
        let matchesRandomStream = await actor.isActiveStream(UUID())
        XCTAssertTrue(matchesActiveStream)
        XCTAssertFalse(matchesRandomStream)

        _ = await actor.apply(.beginFinalizing)
        var snapshot = await actor.apply(.markFailed("boom"))
        XCTAssertEqual(snapshot.lifecycle, .failed("boom"))

        let replacement = ReplyRuntimeState(
            assistantReplyID: AssistantReplyID(),
            messageID: UUID(),
            conversationID: UUID(),
            lifecycle: .completed
        )
        await actor.replaceState(with: replacement)
        snapshot = await actor.snapshot()
        XCTAssertEqual(snapshot, replacement)
        let matchesAfterReplace = await actor.isActiveStream(streamID)
        XCTAssertFalse(matchesAfterReplace)
    }

    func testSessionVisibilityCoordinatorRendersVisibleStateFromRuntimeSnapshot() {
        let session = makeReplySession()
        let draft = Message(role: .assistant, content: "draft")
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .recoveringStream(
                StreamCursor(
                    responseID: "resp_visible",
                    lastSequenceNumber: 42,
                    route: .gateway
                )
            ),
            buffer: ReplyBuffer(
                text: "visible text",
                thinking: "visible thinking",
                toolCalls: [ToolCallInfo(id: "tool_1", type: .webSearch, status: .searching)],
                citations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
                filePathAnnotations: [
                    FilePathAnnotation(
                        fileId: "file_1",
                        containerId: "ctr_1",
                        sandboxPath: "sandbox:/tmp/report.txt",
                        filename: "report.txt",
                        startIndex: 0,
                        endIndex: 10
                    )
                ]
            ),
            isThinking: true
        )

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: draft
        )

        XCTAssertEqual(visibleState.currentStreamingText, "visible text")
        XCTAssertEqual(visibleState.currentThinkingText, "visible thinking")
        XCTAssertEqual(visibleState.activeToolCalls.count, 1)
        XCTAssertEqual(visibleState.liveCitations.count, 1)
        XCTAssertEqual(visibleState.liveFilePathAnnotations.count, 1)
        XCTAssertEqual(visibleState.lastSequenceNumber, 42)
        XCTAssertEqual(visibleState.activeRequestModel, .gpt5_4)
        XCTAssertEqual(visibleState.activeRequestEffort, .high)
        XCTAssertTrue(visibleState.isStreaming)
        XCTAssertTrue(visibleState.isRecovering)
        XCTAssertTrue(visibleState.isThinking)
        XCTAssertEqual(visibleState.draftMessage?.id, draft.id)
    }

    func testSessionVisibilityCoordinatorClearedStateOptionallyRetainsDraft() {
        let draft = Message(role: .assistant, content: "draft")

        let retained = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: false)
        XCTAssertEqual(retained.draftMessage?.id, draft.id)
        XCTAssertFalse(retained.isRecovering)

        let cleared = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: true)
        XCTAssertNil(cleared.draftMessage)
        XCTAssertFalse(cleared.isStreaming)
    }

    func testReplySessionSnapshotReflectsRuntimeSnapshot() {
        let session = makeReplySession()
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .streaming(
                StreamCursor(
                    responseID: "resp_save",
                    lastSequenceNumber: 11,
                    route: .gateway
                )
            ),
            buffer: ReplyBuffer(
                text: "streaming text",
                thinking: "streaming reasoning",
                toolCalls: [ToolCallInfo(id: "tool_1", type: .webSearch, status: .completed)],
                citations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
                filePathAnnotations: [
                    FilePathAnnotation(
                        fileId: "file_1",
                        containerId: "ctr_1",
                        sandboxPath: "sandbox:/tmp/report.txt",
                        filename: "report.txt",
                        startIndex: 0,
                        endIndex: 10
                    )
                ]
            )
        )

        let snapshot = ReplySessionSnapshot(session: session, runtimeState: runtimeState)
        XCTAssertEqual(snapshot.currentText, "streaming text")
        XCTAssertEqual(snapshot.currentThinking, "streaming reasoning")
        XCTAssertEqual(snapshot.toolCalls.count, 1)
        XCTAssertEqual(snapshot.citations.count, 1)
        XCTAssertEqual(snapshot.filePathAnnotations.count, 1)
        XCTAssertEqual(snapshot.lastSequenceNumber, 11)
        XCTAssertEqual(snapshot.responseId, "resp_save")
        XCTAssertTrue(snapshot.requestUsesBackgroundMode)
    }

    func testMessagePersistenceAdapterPersistsDraftCompletedAndPartialSnapshots() {
        let adapter = MessagePersistenceAdapter()
        let conversation = Conversation(title: "Persistence")
        let draftMessage = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            isComplete: false
        )

        let draftSnapshot = ReplySessionSnapshot(
            currentText: "draft text",
            currentThinking: "draft thinking",
            toolCalls: [ToolCallInfo(id: "tool_1", type: .webSearch, status: .searching)],
            citations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
            filePathAnnotations: [],
            lastSequenceNumber: 9,
            responseId: "resp_draft",
            requestUsesBackgroundMode: true
        )
        adapter.saveDraftState(from: draftSnapshot, to: draftMessage)
        XCTAssertEqual(draftMessage.content, "draft text")
        XCTAssertEqual(draftMessage.thinking, "draft thinking")
        XCTAssertEqual(draftMessage.lastSequenceNumber, 9)
        XCTAssertEqual(draftMessage.responseId, "resp_draft")
        XCTAssertFalse(draftMessage.isComplete)

        let completedSnapshot = ReplySessionSnapshot(
            currentText: "final text",
            currentThinking: "final thinking",
            toolCalls: [],
            citations: [],
            filePathAnnotations: [],
            lastSequenceNumber: 12,
            responseId: "resp_complete",
            requestUsesBackgroundMode: false
        )
        adapter.finalizeCompletedSession(from: completedSnapshot, to: draftMessage)
        XCTAssertEqual(draftMessage.content, "final text")
        XCTAssertEqual(draftMessage.thinking, "final thinking")
        XCTAssertNil(draftMessage.lastSequenceNumber)
        XCTAssertEqual(draftMessage.responseId, "resp_complete")
        XCTAssertTrue(draftMessage.isComplete)

        let partialSnapshot = ReplySessionSnapshot(
            currentText: "",
            currentThinking: "",
            toolCalls: [],
            citations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
            filePathAnnotations: [],
            lastSequenceNumber: 3,
            responseId: "resp_partial",
            requestUsesBackgroundMode: false
        )
        adapter.finalizePartialSession(from: partialSnapshot, to: draftMessage)
        XCTAssertEqual(draftMessage.content, "final text")
        XCTAssertEqual(draftMessage.responseId, "resp_partial")
        XCTAssertTrue(draftMessage.isComplete)
    }

    @MainActor
    private func makeReplySession() -> ReplySession {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: "seed",
            thinking: "plan",
            lastSequenceNumber: 17,
            usedBackgroundMode: true,
            isComplete: false
        )
        return ReplySession(
            message: message,
            conversationID: UUID(),
            request: ResponseRequestContext(
                apiKey: "sk-test",
                messages: nil,
                model: .gpt5_4,
                effort: .high,
                usesBackgroundMode: true,
                serviceTier: .standard
            )
        )
    }

    private func makeRuntimeState() -> ReplyRuntimeState {
        ReplyRuntimeState(
            assistantReplyID: AssistantReplyID(),
            messageID: UUID(),
            conversationID: UUID()
        )
    }
}
