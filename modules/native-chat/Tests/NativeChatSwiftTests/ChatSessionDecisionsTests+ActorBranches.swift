import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@MainActor
extension ChatSessionDecisionsTests {
    @Test func `reply session actor covers lifecycle branch transitions`() async {
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

    @Test func `reply session actor covers duplicate tool and annotation no ops`() async {
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

    @Test func `reply session actor covers recovery status and poll branches`() async {
        let actor = makeRecoveringStatusActor()

        var snapshot = await actor.apply(.recordResponseCreated("resp_updated", route: .gateway))
        guard case let .streaming(updatedCursor) = snapshot.lifecycle else {
            Issue.record("Expected streaming cursor after recovery response metadata")
            return
        }
        #expect(updatedCursor.responseID == "resp_updated")
        #expect(!snapshot.isRecovering)

        snapshot = await actor.apply(.recordSequenceUpdate(9))
        #expect(snapshot.lastSequenceNumber == 9)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case let .recoveringPoll(pollTicket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll ticket")
            return
        }
        #expect(pollTicket.usedBackgroundMode)
        #expect(pollTicket.lastSequenceNumber == 9)
    }

    @Test func `reply session actor covers detach and failed branches`() async {
        let actor = makeRecoveringStatusActor()

        var snapshot = await actor.apply(.detachForBackground(usedBackgroundMode: true))
        guard case let .detached(detachedTicket) = snapshot.lifecycle else {
            Issue.record("Expected detached lifecycle")
            return
        }
        #expect(detachedTicket.usedBackgroundMode)

        let failedActor = ReplySessionActor(initialState: makeRuntimeState())
        snapshot = await failedActor.apply(.detachForBackground(usedBackgroundMode: false))
        #expect(snapshot.lifecycle == .failed(nil))
    }

    @Test func `runtime registry actor start lookup and remove paths`() async {
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

    @Test func `reply session actor replace state and active stream queries`() async {
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
}
