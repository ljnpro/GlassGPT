import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@MainActor
struct ChatSessionDecisionsTests {
    @Test func `recovery resume mode uses streaming when background mode and sequence exist`() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        #expect(mode == .stream(lastSequenceNumber: 42))
    }

    @Test func `recovery resume mode streams when caller prefers resume and a cursor exists`() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 42
        )

        #expect(mode == .stream(lastSequenceNumber: 42))
    }

    @Test func `gateway fallback triggers direct resume when no recovery events arrive`() {
        #expect(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                resumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
    }

    @Test func `poll after recovery stream when recoverable failure occurs or response still tracked`() {
        #expect(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: true,
                responseId: nil
            )
        )
        #expect(
            RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: "resp_123"
            )
        )
        #expect(
            !RuntimeSessionDecisionPolicy.shouldPollAfterRecoveryStream(
                encounteredRecoverableFailure: false,
                responseId: nil
            )
        )
    }

    @Test func `pending background cancellation and detach only apply to background responses`() {
        let messageId = UUID()

        #expect(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_123",
                messageId: messageId
            )
                == RuntimePendingBackgroundCancellation(responseId: "resp_123", messageId: messageId)
        )
        #expect(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: false,
                responseId: "resp_123",
                messageId: messageId
            ) == nil
        )

        #expect(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
        #expect(
            !RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: false,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
    }

    @Test func `reply session actor owns streaming lifecycle`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        var snapshot = await actor.apply(.beginSubmitting)
        #expect(snapshot.lifecycle == .preparingInput)
        #expect(!snapshot.isThinking)

        snapshot = await actor.apply(.beginStreaming(streamID: UUID(), route: .gateway))
        #expect(snapshot.lifecycle == .preparingInput)

        snapshot = await actor.apply(.recordResponseCreated("resp_stream", route: .gateway))
        guard case let .streaming(cursor) = snapshot.lifecycle else {
            Issue.record("Expected streaming lifecycle after response creation")
            return
        }
        #expect(cursor.responseID == "resp_stream")
        #expect(cursor.lastSequenceNumber == nil)

        snapshot = await actor.apply(.recordSequenceUpdate(8))
        #expect(snapshot.lastSequenceNumber == 8)
    }

    @Test func `reply session actor owns recovery lifecycle and completion`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.beginSubmitting)
        _ = await actor.apply(.recordResponseCreated("resp_stream", route: .gateway))
        _ = await actor.apply(.recordSequenceUpdate(8))

        var snapshot = await actor.apply(
            .beginRecoveryStatus(
                responseID: "resp_stream",
                lastSequenceNumber: 8,
                usedBackgroundMode: true,
                route: .gateway
            )
        )
        guard case let .recoveringStatus(ticket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStatus lifecycle")
            return
        }
        #expect(ticket.responseID == "resp_stream")
        #expect(ticket.lastSequenceNumber == 8)
        #expect(snapshot.isRecovering)

        snapshot = await actor.apply(.beginRecoveryStream(streamID: UUID()))
        guard case let .recoveringStream(recoveryCursor) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStream lifecycle")
            return
        }
        #expect(recoveryCursor.responseID == "resp_stream")
        #expect(snapshot.isStreaming)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case let .recoveringPoll(pollTicket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll lifecycle")
            return
        }
        #expect(pollTicket.responseID == "resp_stream")

        snapshot = await actor.apply(.markCompleted)
        #expect(snapshot.lifecycle == .completed)
        #expect(!snapshot.isRecovering)
        #expect(!snapshot.isThinking)
    }

    @Test func `recovery metadata progress clears recovering lifecycle before visible content arrives`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(
            .beginRecoveryStatus(
                responseID: "resp_resume",
                lastSequenceNumber: 7,
                usedBackgroundMode: true,
                route: .gateway
            )
        )
        var snapshot = await actor.apply(.recordResponseCreated("resp_resume", route: .gateway))

        guard case let .streaming(cursor) = snapshot.lifecycle else {
            Issue.record("Expected streaming lifecycle after responseCreated during recovery")
            return
        }
        #expect(cursor.responseID == "resp_resume")
        #expect(!snapshot.isRecovering)
        #expect(snapshot.isStreaming)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case .recoveringPoll = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll lifecycle")
            return
        }

        snapshot = await actor.apply(.recordSequenceUpdate(12))
        guard case let .streaming(updatedCursor) = snapshot.lifecycle else {
            Issue.record("Expected streaming lifecycle after sequenceUpdate during recovery")
            return
        }
        #expect(updatedCursor.lastSequenceNumber == 12)
        #expect(!snapshot.isRecovering)
        #expect(snapshot.isStreaming)
    }
}

// MARK: - Helpers

extension ChatSessionDecisionsTests {
    @MainActor
    func makeReplySession() -> ReplySession {
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

    func makeRuntimeState() -> ReplyRuntimeState {
        ReplyRuntimeState(
            assistantReplyID: AssistantReplyID(),
            messageID: UUID(),
            conversationID: UUID()
        )
    }
}
