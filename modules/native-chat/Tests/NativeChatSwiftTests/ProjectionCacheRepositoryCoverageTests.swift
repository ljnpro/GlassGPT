import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData
import Testing
@testable import ChatProjectionPersistence

struct ProjectionCacheRepositoryCoverageTests {
    @MainActor
    @Test
    func `projection cache repository filters removes and purges account scoped data`() throws {
        let container = try makeProjectionCacheContainer()
        let context = ModelContext(container)
        let repository = ProjectionCacheRepository(modelContext: context)

        let chat = try repository.upsertConversation(makeProjectionConversationRecord(
            serverID: "conv_chat",
            accountID: "usr_1",
            title: "Chat",
            mode: .chat,
            updatedAt: .init(timeIntervalSince1970: 3)
        ))
        let agent = try repository.upsertConversation(makeProjectionConversationRecord(
            serverID: "conv_agent",
            accountID: "usr_1",
            title: "Agent",
            mode: .agent,
            createdAt: .init(timeIntervalSince1970: 2),
            updatedAt: .init(timeIntervalSince1970: 4),
            lastRunServerID: "run_2",
            lastSyncCursor: "cur_2"
        ))
        let foreign = try repository.upsertConversation(makeProjectionConversationRecord(
            serverID: "conv_foreign",
            accountID: "usr_2",
            title: "Foreign",
            mode: .chat,
            updatedAt: .init(timeIntervalSince1970: 5)
        ))

        let retainedMessage = repository.upsertMessage(
            makeProjectionMessageRecord(
                serverID: "msg_keep",
                accountID: "usr_1",
                content: "keep",
                completedAt: .init(timeIntervalSince1970: 7),
                serverCursor: "cur_6",
                serverRunID: "run_keep"
            ),
            in: chat
        )
        _ = repository.upsertMessage(
            makeProjectionMessageRecord(
                serverID: "msg_drop",
                accountID: "usr_1",
                content: "drop",
                completedAt: nil,
                serverCursor: "cur_7",
                serverRunID: "run_drop"
            ),
            in: chat
        )
        _ = repository.upsertMessage(
            makeProjectionMessageRecord(
                serverID: "msg_foreign",
                accountID: "usr_2",
                content: "foreign",
                completedAt: .init(timeIntervalSince1970: 7),
                serverCursor: "cur_8",
                serverRunID: "run_foreign"
            ),
            in: foreign
        )
        try repository.save()

        #expect(try repository.fetchConversations(accountID: "usr_1").map(\.id) == [agent.id, chat.id])
        #expect(try repository.fetchConversations(accountID: "usr_1", mode: .chat).map(\.id) == [chat.id])
        #expect(try repository.fetchConversations(accountID: "usr_1", mode: .agent).map(\.id) == [agent.id])

        repository.removeMessages(in: chat, excludingServerIDs: ["msg_keep"])
        try repository.save()

        let updatedChat = try #require(
            try repository.fetchConversation(serverID: "conv_chat", accountID: "usr_1")
        )
        #expect(updatedChat.messages.map(\.id) == [retainedMessage.id])

        try repository.removeConversations(
            for: "usr_1",
            excludingServerIDs: ["conv_chat"]
        )
        try repository.save()

        #expect(try repository.fetchConversation(serverID: "conv_agent", accountID: "usr_1") == nil)
        #expect(try repository.fetchConversation(serverID: "conv_foreign", accountID: "usr_2") != nil)

        try repository.purgeCache(accountID: "usr_1")
        #expect(try repository.fetchConversations(accountID: "usr_1").isEmpty)
        #expect(try repository.fetchConversations(accountID: "usr_2").map(\.id) == [foreign.id])
    }
}

@MainActor
private func makeProjectionCacheContainer() throws -> ModelContainer {
    let schema = Schema([Conversation.self, Message.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func makeProjectionConversationRecord(
    serverID: String,
    accountID: String,
    title: String,
    mode: ConversationMode,
    createdAt: Date = .init(timeIntervalSince1970: 1),
    updatedAt: Date,
    lastRunServerID: String? = nil,
    lastSyncCursor: String? = nil
) -> ConversationProjectionRecord {
    ConversationProjectionRecord(
        serverID: serverID,
        accountID: accountID,
        title: title,
        mode: mode,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastRunServerID: lastRunServerID,
        lastSyncCursor: lastSyncCursor
    )
}

private func makeProjectionMessageRecord(
    serverID: String,
    accountID: String,
    role: MessageRole = .assistant,
    content: String,
    createdAt: Date = .init(timeIntervalSince1970: 6),
    completedAt: Date?,
    serverCursor: String?,
    serverRunID: String?
) -> MessageProjectionRecord {
    MessageProjectionRecord(
        serverID: serverID,
        accountID: accountID,
        role: role,
        content: content,
        thinking: nil,
        createdAt: createdAt,
        completedAt: completedAt,
        serverCursor: serverCursor,
        serverRunID: serverRunID,
        annotations: [],
        toolCalls: [],
        filePathAnnotations: [],
        agentTrace: nil
    )
}
