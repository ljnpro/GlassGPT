import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatProjectionPersistence
import Foundation
import SyncProjection

@MainActor
extension BackendProjectionStore {
    func ensureConversation(
        for event: RunEventDTO,
        accountID: String
    ) throws(PersistenceError) -> Conversation {
        if let cached = try cacheRepository.fetchConversation(
            serverID: event.conversationID,
            accountID: accountID
        ) {
            return cached
        }

        let fallbackConversation = event.conversation ?? ConversationDTO(
            id: event.conversationID,
            title: "Conversation",
            mode: event.run?.kind == .agent ? .agent : .chat,
            createdAt: event.createdAt,
            updatedAt: event.createdAt,
            lastRunID: event.runID,
            lastSyncCursor: event.cursor
        )
        return try cacheRepository.upsertConversation(
            conversationRecord(from: fallbackConversation, accountID: accountID)
        )
    }

    func conversationRecord(
        from conversation: ConversationDTO,
        accountID: String
    ) -> ConversationProjectionRecord {
        ConversationProjectionRecord(
            serverID: conversation.id,
            accountID: accountID,
            title: conversation.title,
            mode: conversation.mode == .agent ? .agent : .chat,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            lastRunServerID: conversation.lastRunID,
            lastSyncCursor: conversation.lastSyncCursor
        )
    }

    func messageRecord(
        from message: MessageDTO,
        accountID: String
    ) -> MessageProjectionRecord {
        MessageProjectionRecord(
            serverID: message.id,
            accountID: accountID,
            role: messageRole(from: message.role),
            content: message.content,
            createdAt: message.createdAt,
            completedAt: message.completedAt,
            serverCursor: message.serverCursor,
            serverRunID: message.runID
        )
    }

    func messageRole(from role: MessageRoleDTO) -> MessageRole {
        switch role {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        case .tool:
            .tool
        }
    }

    func filterEvents(
        _ events: [RunEventDTO],
        after cursor: SyncCursor?
    ) throws(PersistenceError) -> [RunEventDTO] {
        var lastCursor = cursor
        var filtered: [RunEventDTO] = []

        for event in events {
            let eventCursor = SyncCursor(rawValue: event.cursor)
            if let cursor, eventCursor <= cursor {
                continue
            }
            if let lastCursor, eventCursor <= lastCursor {
                throw .migrationFailure(
                    underlying: RunEventProjectionError.eventCursorOutOfOrder(
                        previous: lastCursor,
                        current: eventCursor
                    )
                )
            }
            filtered.append(event)
            lastCursor = eventCursor
        }

        return filtered
    }
}
