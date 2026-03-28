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

        let chat = try repository.upsertConversation(
            ConversationProjectionRecord(
                serverID: "conv_chat",
                accountID: "usr_1",
                title: "Chat",
                mode: .chat,
                createdAt: .init(timeIntervalSince1970: 1),
                updatedAt: .init(timeIntervalSince1970: 3),
                lastRunServerID: nil,
                lastSyncCursor: nil
            )
        )
        let agent = try repository.upsertConversation(
            ConversationProjectionRecord(
                serverID: "conv_agent",
                accountID: "usr_1",
                title: "Agent",
                mode: .agent,
                createdAt: .init(timeIntervalSince1970: 2),
                updatedAt: .init(timeIntervalSince1970: 4),
                lastRunServerID: "run_2",
                lastSyncCursor: "cur_2"
            )
        )
        let foreign = try repository.upsertConversation(
            ConversationProjectionRecord(
                serverID: "conv_foreign",
                accountID: "usr_2",
                title: "Foreign",
                mode: .chat,
                createdAt: .init(timeIntervalSince1970: 1),
                updatedAt: .init(timeIntervalSince1970: 5),
                lastRunServerID: nil,
                lastSyncCursor: nil
            )
        )

        let retainedMessage = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_keep",
                accountID: "usr_1",
                role: .assistant,
                content: "keep",
                createdAt: .init(timeIntervalSince1970: 6),
                completedAt: .init(timeIntervalSince1970: 7),
                serverCursor: "cur_6",
                serverRunID: "run_keep"
            ),
            in: chat
        )
        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_drop",
                accountID: "usr_1",
                role: .assistant,
                content: "drop",
                createdAt: .init(timeIntervalSince1970: 6),
                completedAt: nil,
                serverCursor: "cur_7",
                serverRunID: "run_drop"
            ),
            in: chat
        )
        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_foreign",
                accountID: "usr_2",
                role: .assistant,
                content: "foreign",
                createdAt: .init(timeIntervalSince1970: 6),
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
