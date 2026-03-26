import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func runLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentLeaderPlanningResult {
        let configuration = frozenRunConfiguration(for: execution, conversation: prepared.conversation)
        AgentProcessProjector.updatePhase(
            planningPhase.runPhase,
            leaderStatus: planningPhase.bootstrapStatus,
            on: &execution.snapshot
        )
        AgentProcessProjector.updateLeaderLivePreview(
            status: planningPhase.bootstrapStatus,
            summary: planningPhase.bootstrapSummary,
            on: &execution.snapshot
        )
        AgentRecentUpdateProjector.recordLeaderPhaseMilestone(
            planningPhase.milestoneSummary,
            phase: planningPhase.runPhase,
            on: &execution.snapshot
        )
        AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)

        if let ticket = execution.snapshot.leaderTicket,
           ticket.phase == planningPhase.runPhase,
           let responseID = ticket.responseID,
           !responseID.isEmpty {
            return try await recoverLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                existingTicket: ticket,
                baseInput: baseInput,
                allowReplayFromCheckpoint: true
            )
        }

        return try await startFreshLeaderPlanningPhase(
            planningPhase,
            prepared: prepared,
            execution: execution,
            configuration: configuration,
            baseInput: baseInput,
            allowReplayFromCheckpoint: true
        )
    }

    func startFreshLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        configuration: AgentConversationConfiguration,
        baseInput: [ResponsesInputMessageDTO],
        previousResponseIDOverride: String? = nil,
        fallbackToConversationLeaderChain: Bool = true,
        allowReplayFromCheckpoint: Bool
    ) async throws -> AgentLeaderPlanningResult {
        let checkpointBaseResponseID = previousResponseIDOverride
            ?? (fallbackToConversationLeaderChain
                ? currentAgentState(for: prepared.conversation).responseID(for: .leader)
                : nil)
        updateTicket(
            AgentRunTicket(
                role: .leader,
                phase: planningPhase.runPhase,
                checkpointBaseResponseID: checkpointBaseResponseID,
                backgroundEligible: configuration.backgroundModeEnabled,
                partialOutputText: execution.snapshot.leaderTicket?.partialOutputText ?? "",
                statusText: execution.snapshot.processSnapshot.leaderLiveStatus,
                summaryText: execution.snapshot.processSnapshot.leaderLiveSummary,
                toolCalls: execution.snapshot.leaderTicket?.toolCalls ?? []
            ),
            for: .leader,
            execution: execution,
            conversation: prepared.conversation,
            forceSave: true
        )
        let stream = state.planningEngine.streamPlanningPhase(
            planningPhase,
            apiKey: prepared.apiKey,
            configuration: configuration,
            conversation: prepared.conversation,
            baseInput: baseInput,
            previousResponseIDOverride: checkpointBaseResponseID,
            fallbackToConversationLeaderChain: false
        )

        do {
            guard let result = try await consumeLeaderPlanningStream(
                stream,
                planningPhase: planningPhase,
                prepared: prepared,
                execution: execution,
                initialState: HiddenLeaderStreamState(
                    responseID: nil,
                    checkpointBaseResponseID: checkpointBaseResponseID,
                    lastSequenceNumber: nil,
                    rawText: "",
                    toolCalls: []
                )
            ) else {
                throw AgentRunFailure.incomplete("Leader planning ended before completion.")
            }
            return result
        } catch let failure as AgentRunFailure {
            guard let existingTicket = execution.snapshot.leaderTicket,
                  existingTicket.phase == planningPhase.runPhase
            else {
                throw failure
            }
            return try await recoverLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                existingTicket: existingTicket,
                baseInput: baseInput,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }
}
