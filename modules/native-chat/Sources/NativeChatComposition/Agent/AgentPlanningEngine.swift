import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

struct AgentLeaderPlanningResult {
    let directive: AgentTaggedOutputParser.LeaderDirective
    let responseID: String
}

@MainActor
final class AgentPlanningEngine {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func runTriage(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentLeaderPlanningResult {
        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.triageInput(baseInput: baseInput),
            instructions: AgentPromptBuilder.leaderTriageInstructions(),
            previousResponseID: conversation.agentConversationState?.responseID(for: .leader),
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: OpenAIRequestFactory.defaultChatTools()
        )
        let output = state.responseParser.extractOutputText(from: response)
        return try AgentLeaderPlanningResult(
            directive: AgentTaggedOutputParser.parseLeaderDirective(from: output),
            responseID: requireResponseID(from: response)
        )
    }

    func runReview(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        baseInput: [ResponsesInputMessageDTO],
        snapshot: AgentProcessSnapshot,
        completedTasks: [AgentTask]
    ) async throws -> AgentLeaderPlanningResult {
        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.leaderReviewInput(
                baseInput: baseInput,
                snapshot: snapshot,
                completedTasks: completedTasks
            ),
            instructions: AgentPromptBuilder.leaderReviewInstructions(),
            previousResponseID: conversation.agentConversationState?.responseID(for: .leader),
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: OpenAIRequestFactory.defaultChatTools()
        )
        let output = state.responseParser.extractOutputText(from: response)
        return try AgentLeaderPlanningResult(
            directive: AgentTaggedOutputParser.parseLeaderDirective(from: output),
            responseID: requireResponseID(from: response)
        )
    }

    private func requireResponseID(from response: ResponsesResponseDTO) throws -> String {
        guard let responseID = response.id, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Responses API did not return a response id.")
        }
        return responseID
    }
}
