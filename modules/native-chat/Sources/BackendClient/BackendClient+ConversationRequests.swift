import BackendContracts
import Foundation

@MainActor
public extension BackendClient {
    func fetchConversations() async throws -> [ConversationDTO] {
        var conversations: [ConversationDTO] = []
        var cursor: String?

        while true {
            let page = try await performWithRetry(
                path: "/v1/conversations",
                method: "GET",
                body: String?.none,
                authorizationMode: .required,
                queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
                responseType: ConversationPageDTO.self
            )
            conversations.append(contentsOf: page.items)

            guard page.hasMore else {
                return conversations
            }
            guard let nextCursor = page.nextCursor, nextCursor != cursor else {
                throw BackendAPIError.invalidResponse
            }
            cursor = nextCursor
        }
    }

    func fetchConversationDetail(_ conversationID: String) async throws -> ConversationDetailDTO {
        try await performWithRetry(
            path: "/v1/conversations/\(conversationID)",
            method: "GET",
            body: String?.none,
            authorizationMode: .required,
            responseType: ConversationDetailDTO.self
        )
    }

    func createConversation(
        title: String,
        mode: ConversationModeDTO,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        try await perform(
            path: "/v1/conversations",
            method: "POST",
            body: CreateConversationRequestDTO(
                title: title,
                mode: mode,
                model: model,
                reasoningEffort: reasoningEffort,
                agentWorkerReasoningEffort: agentWorkerReasoningEffort,
                serviceTier: serviceTier
            ),
            authorizationMode: .required,
            responseType: ConversationDTO.self
        )
    }

    func sendMessage(
        _ content: String,
        to conversationID: String,
        imageBase64: String? = nil,
        fileIds: [String]? = nil
    ) async throws -> RunSummaryDTO {
        try await perform(
            path: "/v1/conversations/\(conversationID)/messages",
            method: "POST",
            body: CreateMessageRequestDTO(
                content: content,
                fileIds: fileIds,
                imageBase64: imageBase64
            ),
            authorizationMode: .required,
            responseType: RunSummaryDTO.self
        )
    }

    func startAgentRun(
        prompt: String?,
        in conversationID: String
    ) async throws -> RunSummaryDTO {
        try await perform(
            path: "/v1/conversations/\(conversationID)/agent-runs",
            method: "POST",
            body: StartAgentRunRequestDTO(prompt: prompt),
            authorizationMode: .required,
            responseType: RunSummaryDTO.self
        )
    }

    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        try await performWithRetry(
            path: "/v1/conversations/\(conversationID)/configuration",
            method: "PATCH",
            body: UpdateConversationConfigurationRequestDTO(
                model: model,
                reasoningEffort: reasoningEffort,
                agentWorkerReasoningEffort: agentWorkerReasoningEffort,
                serviceTier: serviceTier
            ),
            authorizationMode: .required,
            responseType: ConversationDTO.self
        )
    }
}
