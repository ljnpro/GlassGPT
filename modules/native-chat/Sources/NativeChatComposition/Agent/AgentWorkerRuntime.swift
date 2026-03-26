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
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String
    ) async throws -> AgentWorkerExecutionResult {
        guard let role = task.owner.role else {
            throw AgentRunFailure.invalidResponse("Leader cannot be used as a worker owner.")
        }

        let existingTicket = execution.snapshot.ticket(for: role)
        if let existingTicket,
           existingTicket.phase == .workerWave,
           existingTicket.taskID == task.id,
           let responseID = existingTicket.responseID,
           !responseID.isEmpty {
            return try await AgentWorkerTaskRecoveryCoordinator.recoverTask(
                in: self,
                task: task,
                role: role,
                apiKey: apiKey,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                existingTicket: existingTicket,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: true
            )
        }

        return try await startFreshTaskRun(
            task,
            role: role,
            apiKey: apiKey,
            configuration: configuration,
            conversation: conversation,
            execution: execution,
            baseInput: baseInput,
            currentFocus: currentFocus,
            decisionSummary: decisionSummary,
            allowReplayFromCheckpoint: true
        )
    }

    func startFreshTaskRun(
        _ task: AgentTask,
        role: AgentRole,
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String,
        previousResponseIDOverride: String? = nil,
        fallbackToConversationRoleChain: Bool = true,
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentWorkerExecutionResult {
        let checkpointBaseResponseID = previousResponseIDOverride
            ?? execution.snapshot.ticket(for: role)?.checkpointBaseResponseID
            ?? (fallbackToConversationRoleChain
                ? conversation.agentConversationState?.responseID(for: role)
                : nil)
        state.runCoordinator.updateTicket(
            AgentRunTicket(
                role: role,
                phase: .workerWave,
                taskID: task.id,
                checkpointBaseResponseID: checkpointBaseResponseID,
                backgroundEligible: configuration.backgroundModeEnabled,
                partialOutputText: execution.snapshot.ticket(for: role)?.partialOutputText ?? "",
                statusText: task.displayStatusText,
                summaryText: task.displaySummary,
                toolCalls: execution.snapshot.ticket(for: role)?.toolCalls ?? []
            ),
            for: role,
            execution: execution,
            conversation: conversation,
            forceSave: true
        )
        let stream = state.serviceFactory().streamResponse(
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
            previousResponseID: checkpointBaseResponseID,
            reasoningEffort: configuration.workerReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: task.toolPolicy == .enabled ? OpenAIRequestFactory.defaultChatTools() : [],
            background: configuration.backgroundModeEnabled
        )

        do {
            guard let result = try await consumeTaskStream(
                stream,
                task: task,
                role: role,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                initialState: AgentWorkerStreamState()
            ) else {
                throw AgentRunFailure.incomplete("Worker task ended before completion.")
            }
            return result
        } catch let failure as AgentRunFailure {
            guard let existingTicket = execution.snapshot.ticket(for: role),
                  existingTicket.phase == .workerWave,
                  existingTicket.taskID == task.id
            else {
                throw failure
            }
            return try await AgentWorkerTaskRecoveryCoordinator.recoverTask(
                in: self,
                task: task,
                role: role,
                apiKey: apiKey,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                existingTicket: existingTicket,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }
}
