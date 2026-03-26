import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func pollLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        responseID: String
    ) async throws -> AgentLeaderPlanningResult {
        let maxAttempts = 30

        for attempt in 0 ..< maxAttempts {
            try Task.checkCancellation()
            let fetched = try await execution.service.fetchResponse(
                responseId: responseID,
                apiKey: prepared.apiKey
            )

            switch fetched.status {
            case .completed:
                applyRecoveredLeaderPreview(
                    outputText: fetched.text,
                    planningPhase: planningPhase,
                    execution: execution
                )
                AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
                execution.markProgress()
                persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)
                return state.planningEngine.parsePlanningResult(from: fetched.text, responseID: responseID)

            case .failed:
                throw AgentRunFailure.invalidResponse(
                    fetched.errorMessage ?? "Leader planning failed."
                )

            case .incomplete:
                throw AgentRunFailure.incomplete(
                    fetched.errorMessage ?? "Leader planning was incomplete."
                )

            case .queued, .inProgress, .unknown:
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }

        throw AgentRunFailure.incomplete("Leader planning timed out while reconnecting.")
    }

    func replayLeaderPlanningFromCheckpoint(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        configuration: AgentConversationConfiguration,
        baseInput: [ResponsesInputMessageDTO],
        checkpointBaseResponseID: String?,
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentLeaderPlanningResult {
        guard allowReplayFromCheckpoint else {
            throw AgentRunFailure.incomplete("Leader planning could not be resumed.")
        }

        clearTicket(
            for: .leader,
            execution: execution,
            conversation: prepared.conversation,
            forceSave: true
        )
        AgentProcessProjector.updateRecoveryState(.replayingCheckpoint, on: &execution.snapshot)
        persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)
        return try await startFreshLeaderPlanningPhase(
            planningPhase,
            prepared: prepared,
            execution: execution,
            configuration: configuration,
            baseInput: baseInput,
            previousResponseIDOverride: checkpointBaseResponseID,
            fallbackToConversationLeaderChain: false,
            allowReplayFromCheckpoint: false
        )
    }

    func resumeOrReplayLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        responseID: String,
        existingTicket: AgentRunTicket,
        configuration: AgentConversationConfiguration,
        baseInput: [ResponsesInputMessageDTO],
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentLeaderPlanningResult {
        if let lastSequenceNumber = existingTicket.lastSequenceNumber {
            let stream = AgentRecoveryStreamMonitoring.monitoredStream(
                execution.service.streamRecovery(
                    responseId: responseID,
                    startingAfter: lastSequenceNumber,
                    apiKey: prepared.apiKey
                ),
                onTimeout: {
                    execution.service.cancelStream()
                }
            )
            do {
                if let recovered = try await consumeLeaderPlanningStream(
                    stream,
                    planningPhase: planningPhase,
                    prepared: prepared,
                    execution: execution,
                    initialState: HiddenLeaderStreamState(
                        responseID: existingTicket.responseID,
                        checkpointBaseResponseID: existingTicket.checkpointBaseResponseID,
                        lastSequenceNumber: existingTicket.lastSequenceNumber,
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
                    "[AgentLeaderPlanningRecoveryCoordinator.resumeOrReplayLeaderPlanningPhase] "
                        + "Stream recovery failed for \(planningPhase.bootstrapStatus): "
                        + "\(error.localizedDescription). Falling back to fetch/poll."
                )
            }
        }

        do {
            return try await pollLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                responseID: responseID
            )
        } catch {
            return try await replayLeaderPlanningFromCheckpoint(
                planningPhase,
                prepared: prepared,
                execution: execution,
                configuration: configuration,
                baseInput: baseInput,
                checkpointBaseResponseID: existingTicket.checkpointBaseResponseID,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }
}
