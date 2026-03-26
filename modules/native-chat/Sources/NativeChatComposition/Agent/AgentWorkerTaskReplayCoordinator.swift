import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

@MainActor
extension AgentWorkerTaskRecoveryCoordinator {
    static func replayTaskFromCheckpoint(
        in runtime: AgentWorkerRuntime,
        task: AgentTask,
        role: AgentRole,
        apiKey: String,
        recoveryService _: OpenAIService,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String,
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentWorkerExecutionResult {
        guard allowReplayFromCheckpoint else {
            throw AgentRunFailure.incomplete("Worker task could not be resumed.")
        }

        let replayBaseResponseID = execution.snapshot.ticket(for: role)?.checkpointBaseResponseID
        runtime.state.runCoordinator.clearTicket(
            for: role,
            execution: execution,
            conversation: conversation,
            forceSave: true
        )
        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: "Replaying last checkpoint",
            summary: "Restarting the worker task from the last saved checkpoint.",
            evidence: [],
            confidence: nil,
            risks: [],
            on: &execution.snapshot
        )
        AgentProcessProjector.updateRecoveryState(.replayingCheckpoint, on: &execution.snapshot)
        runtime.state.runCoordinator.persistCheckpointIfNeeded(execution, in: conversation, forceSave: true)
        return try await runtime.startFreshTaskRun(
            task,
            role: role,
            apiKey: apiKey,
            configuration: configuration,
            conversation: conversation,
            execution: execution,
            baseInput: baseInput,
            currentFocus: currentFocus,
            decisionSummary: decisionSummary,
            previousResponseIDOverride: replayBaseResponseID,
            fallbackToConversationRoleChain: false,
            allowReplayFromCheckpoint: false
        )
    }

    static func resumeOrReplayTask(
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
        if let lastSequenceNumber = existingTicket.lastSequenceNumber {
            let recoveryStream = AgentRecoveryStreamMonitoring.monitoredStream(
                recoveryService.streamRecovery(
                    responseId: responseID,
                    startingAfter: lastSequenceNumber,
                    apiKey: apiKey
                ),
                onTimeout: {
                    recoveryService.cancelStream()
                }
            )
            do {
                if let recovered = try await runtime.consumeTaskStream(
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
                    ),
                    finalizeWhenStreamEnds: false
                ) {
                    return recovered
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                Loggers.persistence.debug(
                    "[AgentWorkerTaskRecoveryCoordinator.resumeOrReplayTask] "
                        + "Stream recovery failed for \(task.id); "
                        + "falling back to fetch/poll: \(error.localizedDescription)"
                )
            }
        }

        do {
            return try await pollRecoveredTask(
                in: runtime,
                task: task,
                role: role,
                apiKey: apiKey,
                recoveryService: recoveryService,
                conversation: conversation,
                execution: execution,
                responseID: responseID
            )
        } catch {
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
    }
}
