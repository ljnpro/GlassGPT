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
        if configuration.backgroundModeEnabled,
           let existingTicket,
           existingTicket.phase == .workerWave,
           existingTicket.taskID == task.id,
           let responseID = existingTicket.responseID,
           !responseID.isEmpty {
            return try await recoverTask(
                task,
                role: role,
                apiKey: apiKey,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                existingTicket: existingTicket
            )
        }

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
            previousResponseID: conversation.agentConversationState?.responseID(for: role),
            reasoningEffort: configuration.workerReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: task.toolPolicy == .enabled ? OpenAIRequestFactory.defaultChatTools() : [],
            background: configuration.backgroundModeEnabled
        )

        return try await consumeTaskStream(
            stream,
            task: task,
            role: role,
            configuration: configuration,
            conversation: conversation,
            execution: execution,
            initialState: AgentWorkerStreamState()
        )
    }

    private func recoverTask(
        _ task: AgentTask,
        role: AgentRole,
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        existingTicket: AgentRunTicket
    ) async throws -> AgentWorkerExecutionResult {
        guard let responseID = existingTicket.responseID else {
            throw AgentRunFailure.incomplete("Worker task could not reconnect.")
        }

        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &execution.snapshot)
        state.runCoordinator.persistCheckpointIfNeeded(execution, in: conversation, forceSave: true)

        let fetched = try await execution.service.fetchResponse(responseId: responseID, apiKey: apiKey)
        switch fetched.status {
        case .completed:
            return finishRecoveredTask(
                task,
                role: role,
                rawText: fetched.text,
                responseID: responseID,
                toolCalls: fetched.toolCalls,
                citations: fetched.annotations,
                execution: execution,
                conversation: conversation
            )
        case .failed:
            throw AgentRunFailure.invalidResponse(fetched.errorMessage ?? "Worker task failed.")
        case .incomplete:
            throw AgentRunFailure.incomplete(fetched.errorMessage ?? "Worker task was incomplete.")
        case .queued, .inProgress, .unknown:
            if let lastSequenceNumber = existingTicket.lastSequenceNumber {
                let recoveryStream = execution.service.streamRecovery(
                    responseId: responseID,
                    startingAfter: lastSequenceNumber,
                    apiKey: apiKey
                )
                return try await consumeTaskStream(
                    recoveryStream,
                    task: task,
                    role: role,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    initialState: AgentWorkerStreamState(
                        responseID: existingTicket.responseID,
                        rawText: existingTicket.partialOutputText,
                        toolCalls: existingTicket.toolCalls
                    )
                )
            }

            return try await pollRecoveredTask(
                task,
                role: role,
                apiKey: apiKey,
                conversation: conversation,
                execution: execution,
                responseID: responseID
            )
        }
    }

    private func pollRecoveredTask(
        _ task: AgentTask,
        role: AgentRole,
        apiKey: String,
        conversation: Conversation,
        execution: AgentExecutionState,
        responseID: String
    ) async throws -> AgentWorkerExecutionResult {
        let maxAttempts = 30

        for attempt in 0 ..< maxAttempts {
            try Task.checkCancellation()
            let fetched = try await execution.service.fetchResponse(responseId: responseID, apiKey: apiKey)

            switch fetched.status {
            case .completed:
                return finishRecoveredTask(
                    task,
                    role: role,
                    rawText: fetched.text,
                    responseID: responseID,
                    toolCalls: fetched.toolCalls,
                    citations: fetched.annotations,
                    execution: execution,
                    conversation: conversation
                )
            case .failed:
                throw AgentRunFailure.invalidResponse(fetched.errorMessage ?? "Worker task failed.")
            case .incomplete:
                throw AgentRunFailure.incomplete(fetched.errorMessage ?? "Worker task was incomplete.")
            case .queued, .inProgress, .unknown:
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }

        throw AgentRunFailure.incomplete("Worker task timed out while reconnecting.")
    }
}
