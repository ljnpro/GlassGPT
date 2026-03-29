import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import Foundation

@MainActor
final class UITestBackendRequester: BackendRequesting {
    private let healthyConnection = ConnectionCheckDTO(
        backend: .healthy,
        auth: .healthy,
        openaiCredential: .healthy,
        sse: .healthy,
        checkedAt: .now,
        latencyMilliseconds: 12,
        errorSummary: nil
    )

    func cancelRun(_ runID: String) async throws -> RunSummaryDTO {
        try makeRun(id: runID, kind: .agent)
    }

    func createConversation(
        title: String,
        mode: ConversationModeDTO,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        ConversationDTO(
            id: "conv_created_1",
            title: title,
            mode: mode,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: nil,
            lastSyncCursor: nil,
            model: model,
            reasoningEffort: reasoningEffort,
            agentWorkerReasoningEffort: agentWorkerReasoningEffort,
            serviceTier: serviceTier
        )
    }

    func fetchConversationDetail(_ conversationID: String) async throws -> ConversationDetailDTO {
        ConversationDetailDTO(
            conversation: ConversationDTO(
                id: conversationID,
                title: "UITest Conversation",
                mode: .chat,
                createdAt: .now,
                updatedAt: .now,
                lastRunID: nil,
                lastSyncCursor: nil
            ),
            messages: [],
            runs: []
        )
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        []
    }

    func fetchCurrentUser() async throws -> UserDTO {
        UITestScenarioAppStoreFactory.makeSession().user
    }

    func fetchRun(_ runID: String) async throws -> RunSummaryDTO {
        try makeRun(id: runID, kind: .agent)
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        healthyConnection
    }

    func authenticateWithApple(
        _: AppleSignInPayload,
        deviceID _: String
    ) async throws -> SessionDTO {
        UITestScenarioAppStoreFactory.makeSession()
    }

    func refreshSession() async throws -> SessionDTO {
        UITestScenarioAppStoreFactory.makeSession()
    }

    func retryRun(_ runID: String) async throws -> RunSummaryDTO {
        try makeRun(id: runID, kind: .agent)
    }

    func sendMessage(_ content: String, to conversationID: String) async throws -> RunSummaryDTO {
        try makeRun(id: "run_chat_1", kind: .chat, conversationID: conversationID, summary: content)
    }

    func startAgentRun(prompt: String?, in conversationID: String) async throws -> RunSummaryDTO {
        try makeRun(id: "run_agent_1", kind: .agent, conversationID: conversationID, summary: prompt)
    }

    func streamRun(_ runID: String, lastEventID _: String?) -> BackendSSEStream {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "localhost"
        components.path = "/v1/runs/\(runID)/stream"
        let url = components.url ?? URL(fileURLWithPath: "/")
        return BackendSSEStream(
            url: url,
            urlSession: .shared,
            authorizationHeader: nil
        )
    }

    func syncEvents(after cursor: String?) async throws -> SyncEnvelopeDTO {
        SyncEnvelopeDTO(nextCursor: cursor, events: [])
    }

    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        ConversationDTO(
            id: conversationID,
            title: "UITest Conversation",
            mode: agentWorkerReasoningEffort == nil ? .chat : .agent,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: nil,
            lastSyncCursor: nil,
            model: model,
            reasoningEffort: reasoningEffort,
            agentWorkerReasoningEffort: agentWorkerReasoningEffort,
            serviceTier: serviceTier
        )
    }

    func logout() async throws {}

    func storeOpenAIKey(_: String) async throws -> CredentialStatusDTO {
        CredentialStatusDTO(provider: "openai", state: .valid, checkedAt: .now, lastErrorSummary: nil)
    }

    func deleteOpenAIKey() async throws {}

    private func makeRun(
        id: String,
        kind: RunKindDTO,
        conversationID: String = "conv_uitest",
        summary: String? = "UITest run"
    ) throws -> RunSummaryDTO {
        RunSummaryDTO(
            id: id,
            conversationID: conversationID,
            kind: kind,
            status: .running,
            stage: kind == .agent ? .finalSynthesis : nil,
            createdAt: .now,
            updatedAt: .now,
            lastEventCursor: "cursor_1",
            visibleSummary: summary,
            processSnapshotJSON: nil
        )
    }
}
