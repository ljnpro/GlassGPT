import Foundation
import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import OpenAITransport
import Testing
@testable import NativeChatComposition

@MainActor
struct ChatSessionDecisionsTests {
    @Test func recoveryResumeModeUsesStreamingWhenBackgroundModeAndSequenceExist() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: true,
            lastSequenceNumber: 42
        )

        #expect(mode == .stream(lastSequenceNumber: 42))
    }

    @Test func recoveryResumeModeFallsBackToPollingWhenBackgroundModeIsDisabled() {
        let mode = RuntimeSessionDecisionPolicy.recoveryResumeMode(
            preferStreamingResume: true,
            usedBackgroundMode: false,
            lastSequenceNumber: 42
        )

        #expect(mode == .poll)
    }

    @Test func gatewayFallbackTriggersDirectResumeWhenNoRecoveryEventsArrive() {
        #expect(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
    }

    @Test func pollAfterRecoveryStreamWhenRecoverableFailureOccursOrResponseStillTracked() {
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

    @Test func pendingBackgroundCancellationAndDetachOnlyApplyToBackgroundResponses() {
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

    @Test func replySessionActorOwnsStreamingLifecycle() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        var snapshot = await actor.apply(.beginSubmitting)
        #expect(snapshot.lifecycle == .preparingInput)
        #expect(!snapshot.isThinking)

        snapshot = await actor.apply(.beginStreaming(streamID: UUID(), route: .gateway))
        #expect(snapshot.lifecycle == .preparingInput)

        snapshot = await actor.apply(.recordResponseCreated("resp_stream", route: .gateway))
        guard case .streaming(let cursor) = snapshot.lifecycle else {
            Issue.record("Expected streaming lifecycle after response creation")
            return
        }
        #expect(cursor.responseID == "resp_stream")
        #expect(cursor.lastSequenceNumber == nil)

        snapshot = await actor.apply(.recordSequenceUpdate(8))
        #expect(snapshot.lastSequenceNumber == 8)
    }

    @Test func replySessionActorOwnsRecoveryLifecycleAndCompletion() async {
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
        guard case .recoveringStatus(let ticket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStatus lifecycle")
            return
        }
        #expect(ticket.responseID == "resp_stream")
        #expect(ticket.lastSequenceNumber == 8)
        #expect(snapshot.isRecovering)

        snapshot = await actor.apply(.beginRecoveryStream(streamID: UUID()))
        guard case .recoveringStream(let recoveryCursor) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStream lifecycle")
            return
        }
        #expect(recoveryCursor.responseID == "resp_stream")
        #expect(snapshot.isStreaming)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case .recoveringPoll(let pollTicket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll lifecycle")
            return
        }
        #expect(pollTicket.responseID == "resp_stream")

        snapshot = await actor.apply(.markCompleted)
        #expect(snapshot.lifecycle == .completed)
        #expect(!snapshot.isRecovering)
        #expect(!snapshot.isThinking)
    }

    @Test func replySessionActorAccumulatedBufferAndToolMutations() async {
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
        #expect(snapshot.buffer.text == "Hello world")
        #expect(snapshot.buffer.thinking == "Plan")
        #expect(snapshot.isThinking)
        #expect(snapshot.buffer.toolCalls.count == 1)
        #expect(snapshot.buffer.toolCalls.first?.status == .searching)
        #expect(snapshot.buffer.toolCalls.first?.code == "print(\"ok\")")
        #expect(snapshot.buffer.citations.count == 1)
        #expect(snapshot.buffer.filePathAnnotations.count == 1)
    }

    @Test func replySessionActorMergesTerminalPayloadAndSupportsCancellation() async {
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
        #expect(snapshot.buffer.text == "final")
        #expect(snapshot.buffer.thinking == "reasoning")
        #expect(snapshot.buffer.filePathAnnotations.count == 1)

        snapshot = await actor.apply(.cancelStreaming)
        #expect(snapshot.lifecycle == .idle)
        #expect(!snapshot.isThinking)
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
