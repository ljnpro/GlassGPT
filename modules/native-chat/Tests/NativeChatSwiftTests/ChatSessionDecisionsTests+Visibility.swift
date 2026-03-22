import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@MainActor
extension ChatSessionDecisionsTests {
    @Test func `session visibility coordinator renders visible state from runtime snapshot`() {
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
        #expect(!visibleState.isRecovering)
        #expect(visibleState.isThinking)
        #expect(visibleState.thinkingPresentationState == .completed)
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

    @Test func `session visibility coordinator cleared state optionally retains draft`() {
        let draft = Message(role: .assistant, content: "draft")

        let retained = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: false)
        #expect(retained.draftMessage?.id == draft.id)
        #expect(!retained.isRecovering)

        let cleared = SessionVisibilityCoordinator.clearedState(retaining: draft, clearDraft: true)
        #expect(cleared.draftMessage == nil)
        #expect(!cleared.isStreaming)
    }

    @Test func `session visibility coordinator preserves recoverable draft placeholder before recovery starts`() {
        let session = makeReplySession()
        let draft = Message(
            role: .assistant,
            content: "Persisted answer",
            thinking: "Persisted reasoning",
            isComplete: false
        )
        draft.responseId = "resp_visible"
        draft.lastSequenceNumber = 11
        draft.usedBackgroundMode = true
        MessagePayloadStore.setToolCalls(
            [ToolCallInfo(id: "ws_1", type: .webSearch, status: .searching)],
            on: draft
        )
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .idle,
            buffer: .init(),
            isThinking: false
        )

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: draft
        )

        #expect(visibleState.currentStreamingText == "Persisted answer")
        #expect(visibleState.currentThinkingText.isEmpty)
        #expect(visibleState.lastSequenceNumber == 11)
        #expect(visibleState.isRecovering)
        #expect(!visibleState.isThinking)
        #expect(visibleState.thinkingPresentationState == nil)
        #expect(visibleState.activeToolCalls == [
            ToolCallInfo(id: "ws_1", type: .webSearch, status: .completed)
        ])
    }

    @Test func `session visibility coordinator keeps detached recoverable draft in recovering placeholder state`() {
        let session = makeReplySession()
        let draft = Message(
            role: .assistant,
            content: "Partial answer",
            thinking: "Partial reasoning",
            responseId: "resp_detached",
            lastSequenceNumber: 7,
            usedBackgroundMode: true,
            isComplete: false
        )
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .detached(
                DetachedRecoveryTicket(
                    assistantReplyID: session.assistantReplyID,
                    messageID: session.messageID,
                    conversationID: session.conversationID,
                    responseID: "resp_detached",
                    lastSequenceNumber: 7,
                    usedBackgroundMode: true,
                    route: .direct
                )
            ),
            buffer: ReplyBuffer(
                text: "Partial answer",
                thinking: "Partial reasoning"
            ),
            isThinking: false
        )

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: draft
        )

        #expect(visibleState.currentStreamingText == "Partial answer")
        #expect(visibleState.currentThinkingText.isEmpty)
        #expect(visibleState.lastSequenceNumber == 7)
        #expect(visibleState.isRecovering)
        #expect(!visibleState.isThinking)
        #expect(visibleState.thinkingPresentationState == nil)
    }

    @Test func `session visibility coordinator preserves draft placeholder while recovery runtime is empty`() {
        let session = makeReplySession()
        let draft = Message(
            role: .assistant,
            content: "Recovered draft text",
            thinking: "Recovered draft reasoning",
            responseId: "resp_placeholder",
            lastSequenceNumber: 5,
            usedBackgroundMode: true,
            isComplete: false
        )
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .recoveringStatus(
                DetachedRecoveryTicket(
                    assistantReplyID: session.assistantReplyID,
                    messageID: session.messageID,
                    conversationID: session.conversationID,
                    responseID: "resp_placeholder",
                    lastSequenceNumber: 5,
                    usedBackgroundMode: true,
                    route: .direct
                )
            ),
            buffer: .init(),
            isThinking: false
        )

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: draft
        )

        #expect(visibleState.currentStreamingText == "Recovered draft text")
        #expect(visibleState.currentThinkingText.isEmpty)
        #expect(visibleState.isRecovering)
        #expect(!visibleState.isThinking)
        #expect(visibleState.thinkingPresentationState == nil)
    }

    @Test func `session visibility coordinator applies only for the registered visible session in the active conversation`() {
        let session = makeReplySession()

        #expect(
            SessionVisibilityCoordinator.canApplyVisibleState(
                targetSession: session,
                visibleMessageID: session.messageID,
                currentConversationID: session.conversationID,
                registeredSession: session
            )
        )
        #expect(
            !SessionVisibilityCoordinator.canApplyVisibleState(
                targetSession: session,
                visibleMessageID: UUID(),
                currentConversationID: session.conversationID,
                registeredSession: session
            )
        )
        #expect(
            !SessionVisibilityCoordinator.canApplyVisibleState(
                targetSession: session,
                visibleMessageID: session.messageID,
                currentConversationID: UUID(),
                registeredSession: session
            )
        )
        #expect(
            !SessionVisibilityCoordinator.canApplyVisibleState(
                targetSession: session,
                visibleMessageID: session.messageID,
                currentConversationID: session.conversationID,
                registeredSession: makeReplySession()
            )
        )
    }

    @Test func `reply session snapshot reflects runtime snapshot`() {
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

    @Test func `message persistence adapter persists draft snapshot`() {
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

    @Test func `message persistence adapter persists completed snapshot`() {
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

    @Test func `message persistence adapter persists partial snapshot`() {
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
