import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

// MARK: - Duplicate, No-Op, and Recovery Branches

@MainActor
extension ChatSessionDecisionsTests {
    @Test func replySessionActorCoversLifecycleBranchTransitions() async {
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
        #expect(snapshot.lifecycle == .uploadingAttachments)

        snapshot = await actor.apply(.beginStreaming(streamID: UUID(), route: .direct))
        #expect(snapshot.lifecycle == .preparingInput)

        let streamingActor = ReplySessionActor(initialState: baseState)
        snapshot = await streamingActor.apply(.beginStreaming(streamID: UUID(), route: .direct))
        #expect(
            snapshot.lifecycle
                == .streaming(StreamCursor(responseID: "resp_branch", lastSequenceNumber: 3, route: .direct))
        )
    }

    @Test func replySessionActorCoversDuplicateToolAndAnnotationNoOps() async {
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

        _ = await actor.apply(.startToolCall(id: "tool_dup", type: .webSearch))
        var snapshot = await actor.apply(.startToolCall(id: "tool_dup", type: .webSearch))
        #expect(snapshot.buffer.toolCalls.count == 1)

        snapshot = await actor.apply(.setToolCallStatus(id: "missing", status: .completed))
        #expect(snapshot.buffer.toolCalls.count == 1)

        snapshot = await actor.apply(.appendToolCode(id: "missing", delta: "ignored"))
        #expect(snapshot.buffer.toolCalls.first?.code == nil)

        snapshot = await actor.apply(.setToolCode(id: "missing", code: "ignored"))
        #expect(snapshot.buffer.toolCalls.first?.code == nil)

        let citation = URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)
        _ = await actor.apply(.addCitation(citation))
        snapshot = await actor.apply(.addCitation(citation))
        #expect(snapshot.buffer.citations.count == 1)

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
        #expect(snapshot.buffer.filePathAnnotations.count == 1)

        snapshot = await actor.apply(.mergeTerminalPayload(text: "", thinking: nil, filePathAnnotations: nil))
        #expect(snapshot.buffer.text == "")
    }

    @Test func replySessionActorCoversRecoveryStatusAndPollBranches() async {
        let actor = makeRecoveringStatusActor()

        var snapshot = await actor.apply(.recordResponseCreated("resp_updated", route: .gateway))
        guard case .recoveringStatus(let updatedStatusTicket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStatus ticket update")
            return
        }
        #expect(updatedStatusTicket.responseID == "resp_updated")

        snapshot = await actor.apply(.recordSequenceUpdate(9))
        #expect(snapshot.lastSequenceNumber == 9)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case .recoveringPoll(let pollTicket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll ticket")
            return
        }
        #expect(pollTicket.usedBackgroundMode)
        #expect(pollTicket.lastSequenceNumber == 9)
    }

    @Test func replySessionActorCoversDetachAndFailedBranches() async {
        let actor = makeRecoveringStatusActor()

        var snapshot = await actor.apply(.detachForBackground(usedBackgroundMode: true))
        guard case .detached(let detachedTicket) = snapshot.lifecycle else {
            Issue.record("Expected detached lifecycle")
            return
        }
        #expect(detachedTicket.usedBackgroundMode)

        let failedActor = ReplySessionActor(initialState: makeRuntimeState())
        snapshot = await failedActor.apply(.detachForBackground(usedBackgroundMode: false))
        #expect(snapshot.lifecycle == .failed(nil))
    }

    private func makeRecoveringStatusActor() -> ReplySessionActor {
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
        return ReplySessionActor(
            initialState: ReplyRuntimeState(
                assistantReplyID: assistantReplyID,
                messageID: messageID,
                conversationID: conversationID,
                lifecycle: .recoveringStatus(ticket)
            )
        )
    }

    @Test func runtimeRegistryActorStartLookupAndRemovePaths() async {
        let registry = RuntimeRegistryActor()
        let messageID = UUID()
        let conversationID = UUID()

        let replyID = await registry.startSession(messageID: messageID, conversationID: conversationID)
        let containsReply = await registry.contains(replyID)
        let activeReplyIDs = await registry.activeReplyIDs()
        #expect(containsReply)
        #expect(activeReplyIDs == [replyID])

        let session = await registry.session(for: replyID)
        #expect(session != nil)

        await registry.remove(replyID)
        let containsReplyAfterRemove = await registry.contains(replyID)
        let activeReplyIDsAfterRemove = await registry.activeReplyIDs()
        #expect(!containsReplyAfterRemove)
        #expect(activeReplyIDsAfterRemove.isEmpty)
    }

    @Test func replySessionActorReplaceStateAndActiveStreamQueries() async {
        let streamID = UUID()
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.beginStreaming(streamID: streamID, route: .gateway))
        let matchesActiveStream = await actor.isActiveStream(streamID)
        let matchesRandomStream = await actor.isActiveStream(UUID())
        #expect(matchesActiveStream)
        #expect(!matchesRandomStream)

        _ = await actor.apply(.beginFinalizing)
        var snapshot = await actor.apply(.markFailed("boom"))
        #expect(snapshot.lifecycle == .failed("boom"))

        let replacement = ReplyRuntimeState(
            assistantReplyID: AssistantReplyID(),
            messageID: UUID(),
            conversationID: UUID(),
            lifecycle: .completed
        )
        await actor.replaceState(with: replacement)
        snapshot = await actor.snapshot()
        #expect(snapshot == replacement)
        let matchesAfterReplace = await actor.isActiveStream(streamID)
        #expect(!matchesAfterReplace)
    }
}

// MARK: - Visibility and Persistence Tests

@MainActor
extension ChatSessionDecisionsTests {
    @Test func sessionVisibilityCoordinatorRendersVisibleStateFromRuntimeSnapshot() {
        let session = makeReplySession()
        let draft = Message(role: .assistant, content: "draft")
        let runtimeState = makeRecoveringStreamRuntimeState(for: session)

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: draft
        )

        #expect(visibleState.currentStreamingText == "visible text")
        #expect(visibleState.currentThinkingText == "visible thinking")
        #expect(visibleState.activeToolCalls.count == 1)
        #expect(visibleState.liveCitations.count == 1)
        #expect(visibleState.liveFilePathAnnotations.count == 1)
        #expect(visibleState.lastSequenceNumber == 42)
        #expect(visibleState.activeRequestModel == .gpt5_4)
        #expect(visibleState.activeRequestEffort == .high)
        #expect(visibleState.isStreaming)
        #expect(visibleState.isRecovering)
        #expect(visibleState.isThinking)
        #expect(visibleState.draftMessage?.id == draft.id)
    }

    private func makeRecoveringStreamRuntimeState(for session: ReplySession) -> ReplyRuntimeState {
        ReplyRuntimeState(
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
    }

    @Test func sessionVisibilityCoordinatorClearedStateOptionallyRetainsDraft() {
        let draft = Message(role: .assistant, content: "draft")

        let retained = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: false)
        #expect(retained.draftMessage?.id == draft.id)
        #expect(!retained.isRecovering)

        let cleared = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: true)
        #expect(cleared.draftMessage == nil)
        #expect(!cleared.isStreaming)
    }

    @Test func replySessionSnapshotReflectsRuntimeSnapshot() {
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
        #expect(snapshot.currentText == "streaming text")
        #expect(snapshot.currentThinking == "streaming reasoning")
        #expect(snapshot.toolCalls.count == 1)
        #expect(snapshot.citations.count == 1)
        #expect(snapshot.filePathAnnotations.count == 1)
        #expect(snapshot.lastSequenceNumber == 11)
        #expect(snapshot.responseId == "resp_save")
        #expect(snapshot.requestUsesBackgroundMode)
    }

    @Test func messagePersistenceAdapterPersistsDraftSnapshot() {
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
        #expect(draftMessage.content == "draft text")
        #expect(draftMessage.thinking == "draft thinking")
        #expect(draftMessage.lastSequenceNumber == 9)
        #expect(draftMessage.responseId == "resp_draft")
        #expect(!draftMessage.isComplete)
    }

    @Test func messagePersistenceAdapterPersistsCompletedSnapshot() {
        let adapter = MessagePersistenceAdapter()
        let conversation = Conversation(title: "Persistence")
        let draftMessage = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            isComplete: false
        )

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
        #expect(draftMessage.content == "final text")
        #expect(draftMessage.thinking == "final thinking")
        #expect(draftMessage.lastSequenceNumber == nil)
        #expect(draftMessage.responseId == "resp_complete")
        #expect(draftMessage.isComplete)
    }

    @Test func messagePersistenceAdapterPersistsPartialSnapshot() {
        let adapter = MessagePersistenceAdapter()
        let conversation = Conversation(title: "Persistence")
        let draftMessage = Message(
            role: .assistant,
            content: "existing content",
            thinking: nil,
            conversation: conversation,
            isComplete: false
        )

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
        #expect(draftMessage.content == "existing content")
        #expect(draftMessage.responseId == "resp_partial")
        #expect(draftMessage.isComplete)
    }
}
