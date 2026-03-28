import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData
import Testing
@testable import ChatPersistenceSwiftData

@Suite(.tags(.persistence))
struct SwiftDataProjectionCacheRepositoryTests {
    @MainActor
    @Test
    func `swiftdata projection cache repository upserts updates prunes and purges account scoped data`() throws {
        let container = try makeSwiftDataProjectionContainer()
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
        _ = try repository.upsertConversation(
            ConversationProjectionRecord(
                serverID: "conv_chat",
                accountID: "usr_1",
                title: "Chat Updated",
                mode: .agent,
                createdAt: .init(timeIntervalSince1970: 1),
                updatedAt: .init(timeIntervalSince1970: 9),
                lastRunServerID: "run_updated",
                lastSyncCursor: "cur_updated"
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

        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_1",
                accountID: "usr_1",
                role: .assistant,
                content: "keep",
                createdAt: .init(timeIntervalSince1970: 6),
                completedAt: .init(timeIntervalSince1970: 7),
                serverCursor: "cur_1",
                serverRunID: "run_1"
            ),
            in: chat
        )
        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_1",
                accountID: "usr_1",
                role: .assistant,
                content: "keep updated",
                createdAt: .init(timeIntervalSince1970: 6),
                completedAt: nil,
                serverCursor: "cur_2",
                serverRunID: "run_2"
            ),
            in: chat
        )
        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_drop",
                accountID: "usr_1",
                role: .user,
                content: "drop",
                createdAt: .init(timeIntervalSince1970: 8),
                completedAt: nil,
                serverCursor: nil,
                serverRunID: nil
            ),
            in: chat
        )
        try repository.save()

        let loaded = try #require(
            try repository.fetchConversation(serverID: "conv_chat", accountID: "usr_1")
        )
        #expect(loaded.title == "Chat Updated")
        #expect(loaded.mode == .agent)
        #expect(loaded.lastRunServerID == "run_updated")
        #expect(loaded.messages.count == 2)
        #expect(try repository.fetchConversations(accountID: "usr_1", mode: .agent).count == 1)

        repository.removeMessages(in: loaded, excludingServerIDs: ["msg_1"])
        try repository.save()
        #expect(loaded.messages.count == 1)
        #expect(loaded.messages.first?.content == "keep updated")
        #expect(loaded.messages.first?.isComplete == false)

        try repository.removeConversations(for: "usr_1", excludingServerIDs: [])
        try repository.save()
        #expect(try repository.fetchConversations(accountID: "usr_1").isEmpty)
        #expect(try repository.fetchConversation(serverID: "conv_foreign", accountID: "usr_2")?.id == foreign.id)

        try repository.purgeCache(accountID: "usr_2")
        #expect(try repository.fetchConversations(accountID: "usr_2").isEmpty)
    }
}

@MainActor
private func makeSwiftDataProjectionContainer() throws -> ModelContainer {
    let schema = Schema([Conversation.self, Message.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
