import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData

/// Repository for the account-scoped local projection cache used by the 5.0 backend-backed app flow.
@MainActor
public final class ProjectionCacheRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func save() throws(PersistenceError) {
        do {
            try modelContext.save()
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    public func fetchConversation(
        serverID: String,
        accountID: String
    ) throws(PersistenceError) -> Conversation? {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conversation in
                    conversation.serverID == serverID && conversation.syncAccountID == accountID
                }
            )
            return try modelContext.fetch(descriptor).first
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    public func fetchConversations(
        accountID: String,
        mode: ConversationMode? = nil
    ) throws(PersistenceError) -> [Conversation] {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conversation in
                    conversation.syncAccountID == accountID
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let conversations = try modelContext.fetch(descriptor)
            guard let mode else {
                return conversations
            }
            return conversations.filter { $0.mode == mode }
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    @discardableResult
    public func upsertConversation(
        _ record: ConversationProjectionRecord
    ) throws(PersistenceError) -> Conversation {
        if let existing = try fetchConversation(
            serverID: record.serverID,
            accountID: record.accountID
        ) {
            apply(record, to: existing)
            return existing
        }

        let conversation = Conversation(
            serverID: record.serverID,
            syncAccountID: record.accountID,
            title: record.title,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            lastRunServerID: record.lastRunServerID,
            lastSyncCursor: record.lastSyncCursor,
            modeRawValue: record.mode == .chat ? nil : record.mode.rawValue
        )
        modelContext.insert(conversation)
        return conversation
    }

    @discardableResult
    public func upsertMessage(
        _ record: MessageProjectionRecord,
        in conversation: Conversation
    ) -> Message {
        if let existing = message(
            serverID: record.serverID,
            accountID: record.accountID,
            conversation: conversation
        ) {
            apply(record, to: existing, conversation: conversation)
            return existing
        }

        let message = Message(
            serverID: record.serverID,
            syncAccountID: record.accountID,
            role: record.role,
            content: record.content,
            createdAt: record.createdAt,
            completedAt: record.completedAt,
            conversation: conversation,
            serverRunID: record.serverRunID,
            serverCursor: record.serverCursor,
            isComplete: record.completedAt != nil
        )
        modelContext.insert(message)
        if !conversation.messages.contains(where: { $0.id == message.id }) {
            conversation.messages.append(message)
        }
        return message
    }

    public func removeMessages(
        in conversation: Conversation,
        excludingServerIDs retainedServerIDs: Set<String>
    ) {
        let staleMessages = conversation.messages.filter { message in
            guard let serverID = message.serverID else {
                return true
            }
            return !retainedServerIDs.contains(serverID)
        }
        for message in staleMessages {
            modelContext.delete(message)
        }
    }

    public func removeConversations(
        for accountID: String,
        excludingServerIDs retainedServerIDs: Set<String>
    ) throws(PersistenceError) {
        let conversations = try fetchConversations(accountID: accountID)
        let staleConversations = conversations.filter { conversation in
            guard let serverID = conversation.serverID else {
                return true
            }
            return !retainedServerIDs.contains(serverID)
        }
        for conversation in staleConversations {
            modelContext.delete(conversation)
        }
    }

    public func purgeCache(accountID: String) throws(PersistenceError) {
        let conversations = try fetchConversations(accountID: accountID)
        for conversation in conversations {
            modelContext.delete(conversation)
        }
        try save()
    }

    private func message(
        serverID: String,
        accountID: String,
        conversation: Conversation
    ) -> Message? {
        conversation.messages.first(where: {
            $0.serverID == serverID && $0.syncAccountID == accountID
        })
    }

    private func apply(_ record: ConversationProjectionRecord, to conversation: Conversation) {
        conversation.serverID = record.serverID
        conversation.syncAccountID = record.accountID
        conversation.title = record.title
        conversation.mode = record.mode
        conversation.createdAt = record.createdAt
        conversation.updatedAt = record.updatedAt
        conversation.lastRunServerID = record.lastRunServerID
        conversation.lastSyncCursor = record.lastSyncCursor
    }

    private func apply(
        _ record: MessageProjectionRecord,
        to message: Message,
        conversation: Conversation
    ) {
        message.serverID = record.serverID
        message.syncAccountID = record.accountID
        message.role = record.role
        message.content = record.content
        message.createdAt = record.createdAt
        message.completedAt = record.completedAt
        message.conversation = conversation
        message.serverRunID = record.serverRunID
        message.serverCursor = record.serverCursor
        message.isComplete = record.completedAt != nil
    }
}
