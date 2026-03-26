import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

enum AgentWorkerTaskRecoveryCoordinator {}

@MainActor
extension AgentWorkerTaskRecoveryCoordinator {
    static func recoverTask(
        in runtime: AgentWorkerRuntime,
        task: AgentTask,
        role: AgentRole,
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        existingTicket: AgentRunTicket,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String,
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentWorkerExecutionResult {
        let recoveryService = runtime.state.serviceFactory()

        guard let responseID = existingTicket.responseID else {
            return try await replayTaskFromCheckpoint(
                in: runtime,
                task: task,
                role: role,
                apiKey: apiKey,
                recoveryService: recoveryService,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }

        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &execution.snapshot)
        runtime.state.runCoordinator.persistCheckpointIfNeeded(execution, in: conversation, forceSave: true)

        if existingTicket.lastSequenceNumber != nil {
            return try await resumeOrReplayTask(
                in: runtime,
                task: task,
                role: role,
                apiKey: apiKey,
                recoveryService: recoveryService,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                responseID: responseID,
                existingTicket: existingTicket,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }

        let fetched: OpenAIResponseFetchResult
        do {
            fetched = try await recoveryService.fetchResponse(responseId: responseID, apiKey: apiKey)
        } catch {
            return try await recoverTaskAfterFetchFailure(
                in: runtime,
                task: task,
                role: role,
                apiKey: apiKey,
                recoveryService: recoveryService,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                responseID: responseID,
                existingTicket: existingTicket,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }

        return try await recoverTask(
            in: runtime,
            task: task,
            role: role,
            apiKey: apiKey,
            recoveryService: recoveryService,
            configuration: configuration,
            conversation: conversation,
            execution: execution,
            responseID: responseID,
            existingTicket: existingTicket,
            baseInput: baseInput,
            currentFocus: currentFocus,
            decisionSummary: decisionSummary,
            allowReplayFromCheckpoint: allowReplayFromCheckpoint,
            fetched: fetched
        )
    }

    private static func recoverTaskAfterFetchFailure(
        in runtime: AgentWorkerRuntime,
        task: AgentTask,
        role: AgentRole,
        apiKey: String,
        recoveryService: OpenAIService,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        responseID: String,
        existingTicket: AgentRunTicket,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String,
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentWorkerExecutionResult {
        try await resumeOrReplayTask(
            in: runtime,
            task: task,
            role: role,
            apiKey: apiKey,
            recoveryService: recoveryService,
            configuration: configuration,
            conversation: conversation,
            execution: execution,
            responseID: responseID,
            existingTicket: existingTicket,
            baseInput: baseInput,
            currentFocus: currentFocus,
            decisionSummary: decisionSummary,
            allowReplayFromCheckpoint: allowReplayFromCheckpoint
        )
    }

    private static func recoverTask(
        in runtime: AgentWorkerRuntime,
        task: AgentTask,
        role: AgentRole,
        apiKey: String,
        recoveryService: OpenAIService,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        responseID: String,
        existingTicket: AgentRunTicket,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String,
        allowReplayFromCheckpoint: Bool,
        fetched: OpenAIResponseFetchResult
    ) async throws -> AgentWorkerExecutionResult {
        switch fetched.status {
        case .completed:
            runtime.finishRecoveredTask(
                task,
                role: role,
                rawText: fetched.text,
                responseID: responseID,
                toolCalls: fetched.toolCalls,
                citations: fetched.annotations,
                execution: execution,
                conversation: conversation
            )
        case .failed, .incomplete:
            try await replayTaskFromCheckpoint(
                in: runtime,
                task: task,
                role: role,
                apiKey: apiKey,
                recoveryService: recoveryService,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        case .queued, .inProgress, .unknown:
            try await recoverTaskAfterFetchFailure(
                in: runtime,
                task: task,
                role: role,
                apiKey: apiKey,
                recoveryService: recoveryService,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                responseID: responseID,
                existingTicket: existingTicket,
                baseInput: baseInput,
                currentFocus: currentFocus,
                decisionSummary: decisionSummary,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }
}
