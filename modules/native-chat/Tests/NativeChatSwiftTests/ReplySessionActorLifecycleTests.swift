import ChatDomain
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import Testing

struct ReplySessionActorLifecycleTests {
    @Test func `begin recovery poll fails when no cursor is available`() async {
        let actor = ReplySessionActor(
            initialState: ReplyRuntimeState(
                assistantReplyID: AssistantReplyID(),
                messageID: UUID(),
                conversationID: UUID(),
                lifecycle: .idle,
                isThinking: true
            )
        )

        let snapshot = await actor.apply(ReplyRuntimeTransition.beginRecoveryPoll)

        #expect(snapshot.lifecycle == ReplyLifecycle.failed(nil as String?))
        #expect(!snapshot.isThinking)
    }
}
