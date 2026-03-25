import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

struct AgentWorkerExecutionResult {
    let task: AgentTask
    let responseID: String
}

@MainActor
final class AgentWorkerRuntime {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func runTask(
        _ task: AgentTask,
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String
    ) async throws -> AgentWorkerExecutionResult {
        guard let role = task.owner.role else {
            throw AgentRunFailure.invalidResponse("Leader cannot be used as a worker owner.")
        }

        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.workerTaskInput(
                baseInput: baseInput,
                task: task,
                currentFocus: currentFocus,
                priorDecisionSummary: decisionSummary
            ),
            instructions: AgentPromptBuilder.workerTaskInstructions(
                for: task.owner,
                toolPolicy: task.toolPolicy
            ),
            previousResponseID: conversation.agentConversationState?.responseID(for: role),
            reasoningEffort: configuration.workerReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: task.toolPolicy == .enabled ? OpenAIRequestFactory.defaultChatTools() : []
        )
        guard let responseID = response.id, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Worker response id is missing.")
        }

        let parsed = AgentTaggedOutputParser.parseWorkerTaskResult(
            from: state.responseParser.extractOutputText(from: response)
        )
        var finishedTask = task
        finishedTask.result = AgentTaskResult(
            summary: parsed.summary,
            evidence: parsed.evidence,
            confidence: parsed.confidence,
            risks: parsed.risks,
            followUpRecommendations: parsed.followUps,
            toolCalls: OpenAIResponseParser.extractToolCalls(from: response),
            citations: OpenAIResponseParser.extractCitations(from: response)
        )
        finishedTask.resultSummary = parsed.summary
        finishedTask.completedAt = .now
        return AgentWorkerExecutionResult(task: finishedTask, responseID: responseID)
    }
}
