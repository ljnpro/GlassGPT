import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import SwiftData
import Testing

@Suite(.tags(.runtime, .persistence))
@MainActor
struct BackendConversationLoaderTests {
    @Test
    func `create conversation round trips chat configuration through backend and projection cache`() async throws {
        let client = LoaderBackendRequester()
        client.createConversationResponse = ConversationDTO(
            id: "conv_chat_01",
            title: "Configured chat",
            mode: .chat,
            createdAt: .init(timeIntervalSince1970: 10),
            updatedAt: .init(timeIntervalSince1970: 11),
            lastRunID: nil,
            lastSyncCursor: nil,
            model: .gpt5_4_pro,
            reasoningEffort: .medium,
            agentWorkerReasoningEffort: nil,
            serviceTier: .flex
        )
        let harness = try makeLoaderHarness(client: client)

        let conversation = try await harness.loader.createConversation(
            title: "Configured chat",
            mode: .chat,
            model: .gpt5_4_pro,
            reasoningEffort: .medium,
            agentWorkerReasoningEffort: nil,
            serviceTier: .flex
        )

        #expect(client.createConversationCalls == [
            CreateConversationCall(
                title: "Configured chat",
                mode: .chat,
                model: .gpt5_4_pro,
                reasoningEffort: .medium,
                agentWorkerReasoningEffort: nil,
                serviceTier: .flex
            )
        ])
        #expect(conversation.serverID == "conv_chat_01")
        #expect(conversation.mode == .chat)
        #expect(conversation.model == ModelType.gpt5_4_pro.rawValue)
        #expect(conversation.reasoningEffort == ReasoningEffort.medium.rawValue)
        #expect(conversation.agentWorkerReasoningEffortRawValue == nil)
        #expect(conversation.serviceTierRawValue == ServiceTier.flex.rawValue)

        let cached = try #require(try harness.loader.loadCachedConversation(serverID: "conv_chat_01"))
        #expect(cached.model == ModelType.gpt5_4_pro.rawValue)
        #expect(cached.reasoningEffort == ReasoningEffort.medium.rawValue)
        #expect(cached.serviceTierRawValue == ServiceTier.flex.rawValue)
    }

    @Test
    func `refresh conversation detail reconciles missing chat configuration from local cache`() async throws {
        let client = LoaderBackendRequester()
        let harness = try makeLoaderHarness(client: client)
        _ = try harness.projectionStore.upsertConversation(
            ConversationDTO(
                id: "conv_chat_01",
                title: "Configured chat",
                mode: .chat,
                createdAt: .init(timeIntervalSince1970: 10),
                updatedAt: .init(timeIntervalSince1970: 11),
                lastRunID: nil,
                lastSyncCursor: "cur_1",
                model: .gpt5_4_pro,
                reasoningEffort: .medium,
                agentWorkerReasoningEffort: nil,
                serviceTier: .flex
            ),
            accountID: "user_1"
        )
        client.detailResponse = ConversationDetailDTO(
            conversation: ConversationDTO(
                id: "conv_chat_01",
                title: "Configured chat",
                mode: .chat,
                createdAt: .init(timeIntervalSince1970: 10),
                updatedAt: .init(timeIntervalSince1970: 12),
                lastRunID: nil,
                lastSyncCursor: "cur_2",
                model: nil,
                reasoningEffort: nil,
                agentWorkerReasoningEffort: nil,
                serviceTier: nil
            ),
            messages: [],
            runs: []
        )
        client.updateConversationResponse = ConversationDTO(
            id: "conv_chat_01",
            title: "Configured chat",
            mode: .chat,
            createdAt: .init(timeIntervalSince1970: 10),
            updatedAt: .init(timeIntervalSince1970: 13),
            lastRunID: nil,
            lastSyncCursor: "cur_2",
            model: .gpt5_4_pro,
            reasoningEffort: .medium,
            agentWorkerReasoningEffort: nil,
            serviceTier: .flex
        )

        let refreshed = try await harness.loader.refreshConversationDetail(serverID: "conv_chat_01")

        #expect(client.updateConversationConfigurationCalls == [
            UpdateConversationConfigurationCall(
                conversationID: "conv_chat_01",
                model: .gpt5_4_pro,
                reasoningEffort: .medium,
                agentWorkerReasoningEffort: nil,
                serviceTier: .flex
            )
        ])
        #expect(refreshed.model == ModelType.gpt5_4_pro.rawValue)
        #expect(refreshed.reasoningEffort == ReasoningEffort.medium.rawValue)
        #expect(refreshed.serviceTierRawValue == ServiceTier.flex.rawValue)
    }

    @Test
    func `refresh conversation detail reconciles missing agent configuration from local cache`() async throws {
        let client = LoaderBackendRequester()
        let harness = try makeLoaderHarness(client: client)
        _ = try harness.projectionStore.upsertConversation(
            ConversationDTO(
                id: "conv_agent_01",
                title: "Configured agent",
                mode: .agent,
                createdAt: .init(timeIntervalSince1970: 20),
                updatedAt: .init(timeIntervalSince1970: 21),
                lastRunID: "run_agent_01",
                lastSyncCursor: "cur_agent_1",
                model: nil,
                reasoningEffort: .high,
                agentWorkerReasoningEffort: .medium,
                serviceTier: .flex
            ),
            accountID: "user_1"
        )
        client.detailResponse = ConversationDetailDTO(
            conversation: ConversationDTO(
                id: "conv_agent_01",
                title: "Configured agent",
                mode: .agent,
                createdAt: .init(timeIntervalSince1970: 20),
                updatedAt: .init(timeIntervalSince1970: 22),
                lastRunID: "run_agent_01",
                lastSyncCursor: "cur_agent_2",
                model: nil,
                reasoningEffort: nil,
                agentWorkerReasoningEffort: nil,
                serviceTier: nil
            ),
            messages: [],
            runs: []
        )
        client.updateConversationResponse = ConversationDTO(
            id: "conv_agent_01",
            title: "Configured agent",
            mode: .agent,
            createdAt: .init(timeIntervalSince1970: 20),
            updatedAt: .init(timeIntervalSince1970: 23),
            lastRunID: "run_agent_01",
            lastSyncCursor: "cur_agent_2",
            model: nil,
            reasoningEffort: .high,
            agentWorkerReasoningEffort: .medium,
            serviceTier: .flex
        )

        let refreshed = try await harness.loader.refreshConversationDetail(serverID: "conv_agent_01")

        #expect(client.updateConversationConfigurationCalls == [
            UpdateConversationConfigurationCall(
                conversationID: "conv_agent_01",
                model: nil,
                reasoningEffort: .high,
                agentWorkerReasoningEffort: .medium,
                serviceTier: .flex
            )
        ])
        #expect(refreshed.mode == .agent)
        #expect(refreshed.reasoningEffort == ReasoningEffort.high.rawValue)
        #expect(refreshed.agentWorkerReasoningEffortRawValue == ReasoningEffort.medium.rawValue)
        #expect(refreshed.serviceTierRawValue == ServiceTier.flex.rawValue)
    }
}
