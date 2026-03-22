import ChatDomain
import ChatPresentation
import ChatRuntimeModel
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@MainActor
extension ChatSessionDecisionsTests {
    @Test func `session visibility coordinator keeps reasoning card in waiting phase until answer text starts`() {
        let session = makeReplySession()
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .streaming(
                StreamCursor(
                    responseID: "resp_waiting",
                    lastSequenceNumber: 4,
                    route: .direct
                )
            ),
            buffer: ReplyBuffer(
                thinking: "Working through the tool results"
            ),
            isThinking: false
        )

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: nil
        )

        #expect(visibleState.thinkingPresentationState == .waiting)
    }

    @Test func `session visibility coordinator marks reasoning complete once answer text arrives even if thinking flag lingers`() {
        let session = makeReplySession()
        let runtimeState = ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .streaming(
                StreamCursor(
                    responseID: "resp_answering",
                    lastSequenceNumber: 5,
                    route: .direct
                )
            ),
            buffer: ReplyBuffer(
                text: "Hi! How can I help?",
                thinking: "Keeping the greeting concise."
            ),
            isThinking: true
        )

        let visibleState = SessionVisibilityCoordinator.visibleState(
            from: session,
            runtimeState: runtimeState,
            draftMessage: nil
        )

        #expect(visibleState.thinkingPresentationState == .completed)
    }
}
