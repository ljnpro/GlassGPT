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
    @Test func `reply session actor accumulated buffer and tool mutations`() async {
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

    @Test func `reply session actor keeps thinking active until terminal transition`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.setThinking(true))
        _ = await actor.apply(.appendText("Hello"))

        var snapshot = await actor.snapshot()
        #expect(snapshot.isThinking)

        _ = await actor.apply(
            .mergeTerminalPayload(
                text: "Hello",
                thinking: "Done",
                filePathAnnotations: nil
            )
        )

        snapshot = await actor.snapshot()
        #expect(!snapshot.isThinking)
    }

    @Test func `reply session actor begins answering by clearing reasoning and active tool calls`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.setThinking(true))
        _ = await actor.apply(.startToolCall(id: "tool_1", type: .webSearch))
        _ = await actor.apply(.setToolCallStatus(id: "tool_1", status: .searching))

        let snapshot = await actor.apply(.beginAnswering(text: "Hello", replace: true))

        #expect(snapshot.buffer.text == "Hello")
        #expect(!snapshot.isThinking)
        #expect(snapshot.buffer.toolCalls.first?.status == .completed)
    }

    @Test func `reply session actor preserves thinking across recovery transitions`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.recordResponseCreated("resp_recovering", route: .direct))
        _ = await actor.apply(.appendThinking("Need to keep reasoning live"))
        _ = await actor.apply(.setThinking(true))

        var snapshot = await actor.apply(
            .beginRecoveryStatus(
                responseID: "resp_recovering",
                lastSequenceNumber: 4,
                usedBackgroundMode: true,
                route: .direct
            )
        )
        #expect(snapshot.isThinking)

        snapshot = await actor.apply(.beginRecoveryPoll)
        #expect(snapshot.isThinking)
    }

    @Test func `reply session actor merges terminal payload and supports cancellation`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())
        let finalAnnotation = FilePathAnnotation(
            fileId: "file_final",
            containerId: "ctr_final",
            sandboxPath: "sandbox:/tmp/final.txt",
            filename: "final.txt",
            startIndex: 0,
            endIndex: 9
        )

        _ = await actor.apply(.recordResponseCreated("resp_terminal", route: .gateway))
        _ = await actor.apply(.appendText("partial"))
        _ = await actor.apply(.appendThinking("draft"))
        _ = await actor.apply(
            .mergeTerminalPayload(
                text: "final",
                thinking: "reasoning",
                filePathAnnotations: [finalAnnotation]
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

    @Test(arguments: [ToolCallStatus.inProgress, .searching, .interpreting, .fileSearching])
    func `reply session actor completes active tool calls when terminal payload arrives`(
        initialStatus: ToolCallStatus
    ) async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.startToolCall(id: "tool_terminal", type: .webSearch))
        _ = await actor.apply(.setToolCallStatus(id: "tool_terminal", status: initialStatus))
        _ = await actor.apply(
            .mergeTerminalPayload(
                text: "done",
                thinking: nil,
                filePathAnnotations: nil
            )
        )

        let snapshot = await actor.snapshot()
        #expect(snapshot.buffer.toolCalls.first?.status == .completed)
    }

    @Test func `reply session actor clears streaming buffer on fresh stream restart`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.appendText("Hi! How can I help?"))
        _ = await actor.apply(.appendThinking("Draft reasoning"))
        _ = await actor.apply(.startToolCall(id: "ws_retry", type: .webSearch))
        _ = await actor.apply(
            .addCitation(
                URLCitation(
                    url: "https://example.com/retry",
                    title: "Retry",
                    startIndex: 0,
                    endIndex: 5
                )
            )
        )

        let snapshot = await actor.apply(.beginStreaming(streamID: UUID(), route: .direct))

        #expect(snapshot.buffer.text.isEmpty)
        #expect(snapshot.buffer.thinking.isEmpty)
        #expect(snapshot.buffer.toolCalls.isEmpty)
        #expect(snapshot.buffer.citations.isEmpty)
        #expect(snapshot.buffer.filePathAnnotations.isEmpty)
    }
}
