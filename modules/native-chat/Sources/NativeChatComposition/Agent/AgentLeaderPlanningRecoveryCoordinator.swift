import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func recoverLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        existingTicket: AgentRunTicket,
        baseInput: [ResponsesInputMessageDTO],
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentLeaderPlanningResult {
        let configuration = frozenRunConfiguration(for: execution, conversation: prepared.conversation)
        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &execution.snapshot)
        persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)

        guard let responseID = existingTicket.responseID, !responseID.isEmpty else {
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

        if existingTicket.lastSequenceNumber != nil {
            return try await resumeOrReplayLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                responseID: responseID,
                existingTicket: existingTicket,
                configuration: configuration,
                baseInput: baseInput,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }

        let fetched: OpenAIResponseFetchResult
        do {
            fetched = try await execution.service.fetchResponse(
                responseId: responseID,
                apiKey: prepared.apiKey
            )
        } catch {
            return try await resumeOrReplayLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                responseID: responseID,
                existingTicket: existingTicket,
                configuration: configuration,
                baseInput: baseInput,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }

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

        case .failed, .incomplete:
            return try await replayLeaderPlanningFromCheckpoint(
                planningPhase,
                prepared: prepared,
                execution: execution,
                configuration: configuration,
                baseInput: baseInput,
                checkpointBaseResponseID: existingTicket.checkpointBaseResponseID,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )

        case .queued, .inProgress, .unknown:
            return try await resumeOrReplayLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                responseID: responseID,
                existingTicket: existingTicket,
                configuration: configuration,
                baseInput: baseInput,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }
}
