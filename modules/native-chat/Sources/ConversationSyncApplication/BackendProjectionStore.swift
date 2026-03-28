import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatProjectionPersistence
import Foundation
import SyncProjection

/// Application-layer cache bridge that materializes backend DTOs into the local SwiftData projection cache.
@MainActor
public final class BackendProjectionStore {
    let cacheRepository: ProjectionCacheRepository
    let cursorStore: SyncCursorStore
    let projector: any RunEventProjecting
    private var projectionStateByAccount: [String: SyncProjectionState] = [:]

    public init(
        cacheRepository: ProjectionCacheRepository,
        cursorStore: SyncCursorStore,
        projector: any RunEventProjecting = DeterministicRunEventProjector()
    ) {
        self.cacheRepository = cacheRepository
        self.cursorStore = cursorStore
        self.projector = projector
    }

    public func loadCachedConversations(
        accountID: String,
        mode: ConversationMode
    ) throws(PersistenceError) -> [Conversation] {
        try cacheRepository.fetchConversations(accountID: accountID, mode: mode)
    }

    public func loadCachedConversation(
        serverID: String,
        accountID: String
    ) throws(PersistenceError) -> Conversation? {
        try cacheRepository.fetchConversation(serverID: serverID, accountID: accountID)
    }

    public func applyConversationIndex(
        _ conversations: [ConversationDTO],
        accountID: String
    ) throws(PersistenceError) {
        try cacheRepository.removeConversations(
            for: accountID,
            excludingServerIDs: Set(conversations.map(\.id))
        )
        for conversation in conversations {
            let record = conversationRecord(from: conversation, accountID: accountID)
            _ = try cacheRepository.upsertConversation(record)
        }
        try cacheRepository.save()
    }

    @discardableResult
    public func upsertConversation(
        _ conversation: ConversationDTO,
        accountID: String
    ) throws(PersistenceError) -> Conversation {
        let cached = try cacheRepository.upsertConversation(
            conversationRecord(from: conversation, accountID: accountID)
        )
        try cacheRepository.save()
        return cached
    }

    @discardableResult
    public func applyConversationDetailSnapshot(
        _ detail: ConversationDetailDTO,
        accountID: String
    ) throws(PersistenceError) -> Conversation {
        let conversationRecord = conversationRecord(from: detail.conversation, accountID: accountID)
        let conversation = try cacheRepository.upsertConversation(conversationRecord)
        let retainedMessageIDs = Set(detail.messages.map(\.id))

        for message in detail.messages {
            let messageRecord = messageRecord(from: message, accountID: accountID)
            _ = cacheRepository.upsertMessage(messageRecord, in: conversation)
        }

        cacheRepository.removeMessages(
            in: conversation,
            excludingServerIDs: retainedMessageIDs
        )
        try cacheRepository.save()
        return conversation
    }

    public func applySyncEnvelope(
        _ envelope: SyncEnvelopeDTO,
        accountID: String
    ) throws(PersistenceError) {
        let currentState = projectionState(for: accountID)
        let filteredEvents = try filterEvents(
            envelope.events,
            after: currentState.cursor
        )
        let filteredEnvelope = SyncEnvelopeDTO(
            nextCursor: envelope.nextCursor,
            events: filteredEvents
        )
        let nextState: SyncProjectionState
        do {
            nextState = try projector.apply(
                batch: SyncProjectionBatch(envelope: filteredEnvelope),
                to: currentState
            )
        } catch {
            throw .migrationFailure(underlying: error)
        }

        for event in filteredEvents {
            if let conversation = event.conversation {
                let record = conversationRecord(from: conversation, accountID: accountID)
                _ = try cacheRepository.upsertConversation(record)
            }

            if let message = event.message {
                let conversation = try ensureConversation(
                    for: event,
                    accountID: accountID
                )
                let record = messageRecord(from: message, accountID: accountID)
                _ = cacheRepository.upsertMessage(record, in: conversation)
            }
        }

        try cacheRepository.save()

        if let cursor = filteredEnvelope.nextCursor {
            cursorStore.persistCursor(cursor, for: accountID)
        }
        projectionStateByAccount[accountID] = nextState
    }

    public func clearAccountCache(accountID: String) throws(PersistenceError) {
        try cacheRepository.purgeCache(accountID: accountID)
        cursorStore.clearCursor(for: accountID)
        projectionStateByAccount.removeValue(forKey: accountID)
    }

    public func projectionState(for accountID: String) -> SyncProjectionState {
        if let state = projectionStateByAccount[accountID] {
            return state
        }

        let cursor = cursorStore.loadCursor(for: accountID).map(SyncCursor.init(rawValue:))
        let state = SyncProjectionState(cursor: cursor)
        projectionStateByAccount[accountID] = state
        return state
    }
}
