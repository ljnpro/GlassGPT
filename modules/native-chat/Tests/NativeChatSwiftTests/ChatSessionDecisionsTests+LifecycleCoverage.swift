import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import Testing

extension ChatSessionDecisionsTests {
    @Test func `reply session actor covers cursorless recovery stream and detach failure branches`() async {
        let streamID = UUID()
        let streamActor = ReplySessionActor(initialState: makeRuntimeState())

        var snapshot = await streamActor.apply(.beginRecoveryStream(streamID: streamID))
        guard case let .recoveringStream(cursor) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStream lifecycle without a prior cursor")
            return
        }
        #expect(cursor.responseID.isEmpty)
        #expect(cursor.lastSequenceNumber == nil)
        #expect(await streamActor.isActiveStream(streamID))

        snapshot = await streamActor.apply(.cancelStreaming)
        #expect(snapshot.lifecycle == .idle)
        #expect(!snapshot.isThinking)
        #expect(await !streamActor.isActiveStream(streamID))

        let detachedActor = ReplySessionActor(initialState: makeRuntimeState())
        snapshot = await detachedActor.apply(.detachForBackground(usedBackgroundMode: true))
        #expect(snapshot.lifecycle == .failed(nil))
        #expect(!snapshot.isThinking)
    }

    @Test func `reply session actor updates recovery tickets as sequence numbers advance`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.recordResponseCreated("resp_recovery", route: .gateway))

        var snapshot = await actor.apply(
            .beginRecoveryStatus(
                responseID: "resp_recovery",
                lastSequenceNumber: nil,
                usedBackgroundMode: true,
                route: .gateway
            )
        )
        guard case let .recoveringStatus(ticket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStatus lifecycle")
            return
        }
        #expect(ticket.lastSequenceNumber == nil)

        snapshot = await actor.apply(.recordSequenceUpdate(4))
        guard case let .recoveringStatus(updatedStatus) = snapshot.lifecycle else {
            Issue.record("Expected recoveringStatus lifecycle after sequence update")
            return
        }
        #expect(updatedStatus.lastSequenceNumber == 4)

        snapshot = await actor.apply(.beginRecoveryPoll)
        guard case let .recoveringPoll(pollTicket) = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll lifecycle")
            return
        }
        #expect(pollTicket.lastSequenceNumber == 4)

        snapshot = await actor.apply(.recordSequenceUpdate(9))
        guard case let .recoveringPoll(updatedPoll) = snapshot.lifecycle else {
            Issue.record("Expected recoveringPoll lifecycle after sequence update")
            return
        }
        #expect(updatedPoll.lastSequenceNumber == 9)

        snapshot = await actor.apply(.detachForBackground(usedBackgroundMode: true))
        guard case let .detached(detachedTicket) = snapshot.lifecycle else {
            Issue.record("Expected detached lifecycle")
            return
        }
        #expect(detachedTicket.lastSequenceNumber == 9)
        #expect(detachedTicket.usedBackgroundMode)
    }

    @Test func `reply session actor covers finalizing and failure lifecycle transitions`() async {
        let actor = ReplySessionActor(initialState: makeRuntimeState())

        _ = await actor.apply(.recordResponseCreated("resp_final", route: .direct))
        _ = await actor.apply(.setThinking(true))

        var snapshot = await actor.apply(.beginFinalizing)
        #expect(snapshot.lifecycle == .finalizing)
        #expect(snapshot.isThinking)

        snapshot = await actor.apply(.markFailed("Timed out"))
        #expect(snapshot.lifecycle == .failed("Timed out"))
        #expect(!snapshot.isThinking)

        snapshot = await actor.apply(.markCompleted)
        #expect(snapshot.lifecycle == .completed)
        #expect(!snapshot.isThinking)
    }
}
