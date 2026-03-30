import BackendAuth
import BackendContracts
import Foundation

@MainActor
public protocol BackendRequesting: AnyObject {
    func cancelRun(_ runID: String) async throws -> RunSummaryDTO
    func createConversation(
        title: String,
        mode: ConversationModeDTO,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO
    func fetchConversationDetail(_ conversationID: String) async throws -> ConversationDetailDTO
    func fetchConversations() async throws -> [ConversationDTO]
    func fetchCurrentUser() async throws -> UserDTO
    func fetchRun(_ runID: String) async throws -> RunSummaryDTO
    func connectionCheck() async throws -> ConnectionCheckDTO
    func authenticateWithApple(_ payload: AppleSignInPayload, deviceID: String) async throws -> SessionDTO
    func refreshSession() async throws -> SessionDTO
    func retryRun(_ runID: String) async throws -> RunSummaryDTO
    func sendMessage(_ content: String, to conversationID: String, imageBase64: String?, fileIds: [String]?) async throws -> RunSummaryDTO
    func startAgentRun(prompt: String?, in conversationID: String) async throws -> RunSummaryDTO
    func streamRun(_ runID: String, lastEventID: String?) async throws -> BackendSSEStream
    func syncEvents(after cursor: String?) async throws -> SyncEnvelopeDTO
    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO
    func logout() async throws
    func storeOpenAIKey(_ apiKey: String) async throws -> CredentialStatusDTO
    func deleteOpenAIKey() async throws
}

@MainActor
public extension BackendRequesting {
    func streamRun(_ runID: String) async throws -> BackendSSEStream {
        try await streamRun(runID, lastEventID: nil)
    }

    func createConversation(title: String, mode: ConversationModeDTO) async throws -> ConversationDTO {
        try await createConversation(
            title: title,
            mode: mode,
            model: nil,
            reasoningEffort: nil,
            agentWorkerReasoningEffort: nil,
            serviceTier: nil
        )
    }

    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        _ = conversationID
        _ = model
        _ = reasoningEffort
        _ = agentWorkerReasoningEffort
        _ = serviceTier
        throw URLError(.unsupportedURL)
    }
}
