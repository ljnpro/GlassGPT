import BackendContracts
import Foundation
import SyncProjection
import Testing

struct RunEventProjectorTests {
    private let projector = DeterministicRunEventProjector()

    @Test
    func `applies a projection-complete batch into indexed state`() throws {
        let batch = SyncProjectionBatch(
            nextCursor: SyncCursor(rawValue: "cur_00000000000000000002"),
            events: [
                makeEvent(
                    id: "evt_01",
                    cursor: "cur_00000000000000000001",
                    kind: .messageCreated,
                    message: makeMessage(
                        id: "msg_01",
                        role: .user,
                        content: "Hello from the user",
                        cursor: "cur_00000000000000000001"
                    ),
                    run: makeRun(status: .queued, cursor: "cur_00000000000000000001"),
                    conversation: makeConversation(cursor: "cur_00000000000000000001")
                ),
                makeEvent(
                    id: "evt_02",
                    cursor: "cur_00000000000000000002",
                    kind: .runQueued,
                    run: makeRun(status: .queued, cursor: "cur_00000000000000000002"),
                    conversation: makeConversation(cursor: "cur_00000000000000000002")
                )
            ]
        )

        let state = try projector.apply(batch: batch, to: .empty)

        #expect(state.cursor == SyncCursor(rawValue: "cur_00000000000000000002"))
        #expect(state.messagesByID["msg_01"]?.content == "Hello from the user")
        #expect(state.runsByID["run_01"]?.status == .queued)
        #expect(state.conversationsByID["conv_01"]?.lastSyncCursor == "cur_00000000000000000002")
    }

    @Test
    func `ignores replayed events once the cursor has already advanced`() throws {
        let priorState = SyncProjectionState(
            cursor: SyncCursor(rawValue: "cur_00000000000000000002"),
            conversationsByID: ["conv_01": makeConversation(cursor: "cur_00000000000000000002")],
            messagesByID: ["msg_01": makeMessage(id: "msg_01", role: .user, content: "Hello", cursor: "cur_00000000000000000001")],
            runsByID: ["run_01": makeRun(status: .queued, cursor: "cur_00000000000000000002")],
            artifactsByID: [:]
        )

        let replayBatch = SyncProjectionBatch(
            nextCursor: SyncCursor(rawValue: "cur_00000000000000000002"),
            events: [
                makeEvent(
                    id: "evt_01",
                    cursor: "cur_00000000000000000001",
                    kind: .messageCreated,
                    message: makeMessage(id: "msg_01", role: .user, content: "Hello", cursor: "cur_00000000000000000001"),
                    run: makeRun(status: .queued, cursor: "cur_00000000000000000001"),
                    conversation: makeConversation(cursor: "cur_00000000000000000001")
                )
            ]
        )

        let replayedState = try projector.apply(batch: replayBatch, to: priorState)

        #expect(replayedState == priorState)
    }

    @Test
    func `rejects non-monotonic event order inside a batch`() throws {
        let batch = SyncProjectionBatch(
            nextCursor: SyncCursor(rawValue: "cur_00000000000000000002"),
            events: [
                makeEvent(id: "evt_02", cursor: "cur_00000000000000000002", kind: .runQueued),
                makeEvent(id: "evt_01", cursor: "cur_00000000000000000001", kind: .messageCreated)
            ]
        )

        #expect(throws: RunEventProjectionError.eventCursorOutOfOrder(
            previous: SyncCursor(rawValue: "cur_00000000000000000002"),
            current: SyncCursor(rawValue: "cur_00000000000000000001")
        )) {
            _ = try projector.apply(batch: batch, to: .empty)
        }
    }
}

private func makeConversation(cursor: String) -> ConversationDTO {
    ConversationDTO(
        id: "conv_01",
        title: "Beta 5.0",
        mode: .chat,
        createdAt: Date(timeIntervalSince1970: 1_774_044_800),
        updatedAt: Date(timeIntervalSince1970: 1_774_044_800),
        lastRunID: "run_01",
        lastSyncCursor: cursor
    )
}

private func makeMessage(
    id: String,
    role: MessageRoleDTO,
    content: String,
    cursor: String
) -> MessageDTO {
    MessageDTO(
        id: id,
        conversationID: "conv_01",
        role: role,
        content: content,
        thinking: nil,
        createdAt: Date(timeIntervalSince1970: 1_774_044_800),
        completedAt: Date(timeIntervalSince1970: 1_774_044_800),
        serverCursor: cursor,
        runID: "run_01",
        annotations: nil,
        toolCalls: nil,
        filePathAnnotations: nil,
        agentTraceJSON: nil
    )
}

private func makeRun(status: RunStatusDTO, cursor: String) -> RunSummaryDTO {
    RunSummaryDTO(
        id: "run_01",
        conversationID: "conv_01",
        kind: .chat,
        status: status,
        stage: nil,
        createdAt: Date(timeIntervalSince1970: 1_774_044_800),
        updatedAt: Date(timeIntervalSince1970: 1_774_044_800),
        lastEventCursor: cursor,
        visibleSummary: "Queued chat run",
        processSnapshotJSON: nil
    )
}

private func makeEvent(
    id: String,
    cursor: String,
    kind: RunEventKindDTO,
    textDelta: String? = nil,
    message: MessageDTO? = nil,
    run: RunSummaryDTO? = nil,
    conversation: ConversationDTO? = nil
) -> RunEventDTO {
    RunEventDTO(
        id: id,
        cursor: cursor,
        runID: "run_01",
        conversationID: "conv_01",
        kind: kind,
        createdAt: Date(timeIntervalSince1970: 1_774_044_800),
        textDelta: textDelta,
        progressLabel: nil,
        stage: nil,
        artifactID: nil,
        conversation: conversation,
        message: message,
        run: run,
        artifact: nil
    )
}
