import ChatDomain
import ChatPersistenceCore

extension ProjectionCacheRepository {
    /// Deletes messages from the conversation that are not in the retained set.
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

    /// Deletes conversations for the account that are not in the retained set.
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

    /// Removes all cached conversations and messages for the given account.
    public func purgeCache(accountID: String) throws(PersistenceError) {
        let conversations = try fetchConversations(accountID: accountID)
        for conversation in conversations {
            modelContext.delete(conversation)
        }
        try save()
    }

    func message(
        serverID: String,
        accountID: String,
        conversation: Conversation
    ) -> Message? {
        conversation.messages.first(where: {
            $0.serverID == serverID && $0.syncAccountID == accountID
        })
    }

    func apply(_ record: ConversationProjectionRecord, to conversation: Conversation) {
        conversation.serverID = record.serverID
        conversation.syncAccountID = record.accountID
        conversation.title = record.title
        conversation.mode = record.mode
        conversation.createdAt = record.createdAt
        conversation.updatedAt = record.updatedAt
        conversation.lastRunServerID = record.lastRunServerID
        conversation.lastSyncCursor = record.lastSyncCursor
        if let model = record.model {
            conversation.model = model
        }
        if let reasoningEffort = record.reasoningEffort {
            conversation.reasoningEffort = reasoningEffort
        }
        if record.mode == .chat {
            conversation.agentWorkerReasoningEffortRawValue = nil
        } else if let agentWorkerReasoningEffort = record.agentWorkerReasoningEffort {
            conversation.agentWorkerReasoningEffortRawValue = agentWorkerReasoningEffort
        }
        if let serviceTier = record.serviceTier {
            conversation.serviceTierRawValue = serviceTier
        }
    }

    func apply(
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
