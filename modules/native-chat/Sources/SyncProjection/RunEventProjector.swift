import BackendContracts
import Foundation

public enum RunEventProjectionError: Error, Equatable, Sendable {
    case batchCursorRegressed(expectedAtLeast: SyncCursor, actual: SyncCursor)
    case eventCursorOutOfOrder(previous: SyncCursor, current: SyncCursor)
}

public protocol RunEventProjecting: Sendable {
    func apply(batch: SyncProjectionBatch, to state: SyncProjectionState) throws -> SyncProjectionState
}

public struct DeterministicRunEventProjector: RunEventProjecting {
    public init() {}

    public func apply(
        batch: SyncProjectionBatch,
        to state: SyncProjectionState
    ) throws -> SyncProjectionState {
        var nextState = state
        let baselineCursor = state.cursor
        var lastAppliedCursor = baselineCursor

        for event in batch.events {
            let eventCursor = SyncCursor(rawValue: event.cursor)
            if let baselineCursor, eventCursor <= baselineCursor {
                continue
            }

            if let previousCursor = lastAppliedCursor, eventCursor <= previousCursor {
                throw RunEventProjectionError.eventCursorOutOfOrder(
                    previous: previousCursor,
                    current: eventCursor
                )
            }

            nextState = upsert(event: event, cursor: eventCursor, into: nextState)
            lastAppliedCursor = eventCursor
        }

        if let batchCursor = batch.nextCursor {
            if let lastAppliedCursor, batchCursor < lastAppliedCursor {
                throw RunEventProjectionError.batchCursorRegressed(
                    expectedAtLeast: lastAppliedCursor,
                    actual: batchCursor
                )
            }

            if let stateCursor = nextState.cursor, batchCursor < stateCursor {
                throw RunEventProjectionError.batchCursorRegressed(
                    expectedAtLeast: stateCursor,
                    actual: batchCursor
                )
            }

            return SyncProjectionState(
                cursor: batchCursor,
                conversationsByID: nextState.conversationsByID,
                messagesByID: nextState.messagesByID,
                runsByID: nextState.runsByID,
                artifactsByID: nextState.artifactsByID
            )
        }

        return nextState
    }

    private func upsert(
        event: RunEventDTO,
        cursor: SyncCursor,
        into state: SyncProjectionState
    ) -> SyncProjectionState {
        var conversationsByID = state.conversationsByID
        var messagesByID = state.messagesByID
        var runsByID = state.runsByID
        var artifactsByID = state.artifactsByID

        if let conversation = event.conversation {
            conversationsByID[conversation.id] = conversation
        }

        if let message = event.message {
            messagesByID[message.id] = message
        }

        if let run = event.run {
            runsByID[run.id] = run
        }

        if let artifact = event.artifact {
            artifactsByID[artifact.id] = artifact
        }

        return SyncProjectionState(
            cursor: cursor,
            conversationsByID: conversationsByID,
            messagesByID: messagesByID,
            runsByID: runsByID,
            artifactsByID: artifactsByID
        )
    }
}
