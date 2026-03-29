import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData

/// Repository for the account-scoped local projection cache used by the 5.0 backend-backed app flow.
@MainActor
public final class ProjectionCacheRepository {
    let modelContext: ModelContext

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
            modeRawValue: record.mode == .chat ? nil : record.mode.rawValue,
            model: record.model ?? ModelType.gpt5_4.rawValue,
            reasoningEffort: record.reasoningEffort ?? ReasoningEffort.high.rawValue,
            agentWorkerReasoningEffortRawValue: record.agentWorkerReasoningEffort,
            serviceTierRawValue: record.serviceTier ?? ServiceTier.standard.rawValue
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
}
