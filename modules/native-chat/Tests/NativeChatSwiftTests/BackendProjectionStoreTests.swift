import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ConversationSyncApplication
import Foundation
import SwiftData
import Testing
@testable import ChatProjectionPersistence

struct BackendProjectionStoreTests {
    @MainActor
    @Test func `projection cache repository upserts server-backed conversations and messages`() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = ProjectionCacheRepository(modelContext: context)

        let conversation = try repository.upsertConversation(
            ConversationProjectionRecord(
                serverID: "conv_123",
                accountID: "usr_123",
                title: "Backend chat",
                mode: .chat,
                createdAt: .init(timeIntervalSince1970: 1),
                updatedAt: .init(timeIntervalSince1970: 2),
                lastRunServerID: "run_1",
                lastSyncCursor: "cur_1"
            )
        )

        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_123",
                accountID: "usr_123",
                role: .assistant,
                content: "first",
                createdAt: .init(timeIntervalSince1970: 3),
                completedAt: nil,
                serverCursor: "cur_2",
                serverRunID: "run_1"
            ),
            in: conversation
        )

        _ = try repository.upsertConversation(
            ConversationProjectionRecord(
                serverID: "conv_123",
                accountID: "usr_123",
                title: "Renamed chat",
                mode: .chat,
                createdAt: .init(timeIntervalSince1970: 1),
                updatedAt: .init(timeIntervalSince1970: 4),
                lastRunServerID: "run_2",
                lastSyncCursor: "cur_3"
            )
        )

        _ = repository.upsertMessage(
            MessageProjectionRecord(
                serverID: "msg_123",
                accountID: "usr_123",
                role: .assistant,
                content: "final",
                createdAt: .init(timeIntervalSince1970: 3),
                completedAt: .init(timeIntervalSince1970: 5),
                serverCursor: "cur_3",
                serverRunID: "run_2"
            ),
            in: conversation
        )

        try repository.save()

        let persistedConversation = try repository.fetchConversation(
            serverID: "conv_123",
            accountID: "usr_123"
        )
        let cachedConversation = try #require(persistedConversation)
        #expect(cachedConversation.title == "Renamed chat")
        #expect(cachedConversation.lastRunServerID == "run_2")
        #expect(cachedConversation.lastSyncCursor == "cur_3")
        #expect(cachedConversation.messages.count == 1)

        let cachedMessage = try #require(cachedConversation.messages.first)
        #expect(cachedMessage.content == "final")
        #expect(cachedMessage.serverRunID == "run_2")
        #expect(cachedMessage.serverCursor == "cur_3")
        #expect(cachedMessage.isComplete)
    }

    @MainActor
    @Test func `backend projection store applies detail and sync events while persisting cursor`() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = ProjectionCacheRepository(modelContext: context)
        let suiteName = "BackendProjectionStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cursorStore = SyncCursorStore(
            valueStore: UserDefaultsSettingsValueStore(defaults: defaults)
        )
        let store = BackendProjectionStore(
            cacheRepository: repository,
            cursorStore: cursorStore
        )

        try store.applyConversationIndex(
            [
                ConversationDTO(
                    id: "conv_abc",
                    title: "Server chat",
                    mode: .chat,
                    createdAt: .init(timeIntervalSince1970: 10),
                    updatedAt: .init(timeIntervalSince1970: 10),
                    lastRunID: nil,
                    lastSyncCursor: "cur_10"
                )
            ],
            accountID: "usr_abc"
        )

        let conversation = try store.applyConversationDetailSnapshot(
            makeConversationDetailSnapshot(),
            accountID: "usr_abc"
        )

        #expect(conversation.messages.count == 1)

        try store.applySyncEnvelope(
            makeSyncEnvelope(),
            accountID: "usr_abc"
        )

        let persistedConversation = try repository.fetchConversation(
            serverID: "conv_abc",
            accountID: "usr_abc"
        )
        let cachedConversation = try #require(persistedConversation)
        #expect(cachedConversation.messages.count == 2)
        #expect(cursorStore.loadCursor(for: "usr_abc") == "cur_12")

        let assistantMessage = try #require(
            cachedConversation.messages.first(where: { $0.serverID == "msg_assistant" })
        )
        #expect(assistantMessage.content == "Hi back")
        #expect(assistantMessage.serverRunID == "run_abc")
    }
}

@MainActor
private func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Conversation.self,
        Message.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func makeConversationDetailSnapshot() -> ConversationDetailDTO {
    ConversationDetailDTO(
        conversation: ConversationDTO(
            id: "conv_abc",
            title: "Server chat",
            mode: .chat,
            createdAt: .init(timeIntervalSince1970: 10),
            updatedAt: .init(timeIntervalSince1970: 11),
            lastRunID: "run_abc",
            lastSyncCursor: "cur_11"
        ),
        messages: [
            MessageDTO(
                id: "msg_user",
                conversationID: "conv_abc",
                role: .user,
                content: "Hello",
                createdAt: .init(timeIntervalSince1970: 11),
                completedAt: .init(timeIntervalSince1970: 11),
                serverCursor: "cur_11",
                runID: nil
            )
        ],
        runs: []
    )
}

private func makeSyncEnvelope() -> SyncEnvelopeDTO {
    SyncEnvelopeDTO(
        nextCursor: "cur_12",
        events: [
            RunEventDTO(
                id: "evt_12",
                cursor: "cur_12",
                runID: "run_abc",
                conversationID: "conv_abc",
                kind: .assistantCompleted,
                createdAt: .init(timeIntervalSince1970: 12),
                textDelta: nil,
                progressLabel: nil,
                stage: nil,
                artifactID: nil,
                conversation: nil,
                message: MessageDTO(
                    id: "msg_assistant",
                    conversationID: "conv_abc",
                    role: .assistant,
                    content: "Hi back",
                    createdAt: .init(timeIntervalSince1970: 12),
                    completedAt: .init(timeIntervalSince1970: 12),
                    serverCursor: "cur_12",
                    runID: "run_abc"
                ),
                run: RunSummaryDTO(
                    id: "run_abc",
                    conversationID: "conv_abc",
                    kind: .chat,
                    status: .completed,
                    stage: nil,
                    createdAt: .init(timeIntervalSince1970: 11),
                    updatedAt: .init(timeIntervalSince1970: 12),
                    lastEventCursor: "cur_12",
                    visibleSummary: nil
                ),
                artifact: nil
            )
        ]
    )
}
