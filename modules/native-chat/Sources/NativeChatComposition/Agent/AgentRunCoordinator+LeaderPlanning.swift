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
        AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: configuration.backgroundModeEnabled)

        if configuration.backgroundModeEnabled,
           let ticket = execution.snapshot.leaderTicket,
           ticket.phase == planningPhase.runPhase,
           let responseID = ticket.responseID,
           !responseID.isEmpty {
            return try await recoverLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                existingTicket: ticket,
                baseInput: baseInput
            )
        }

        let stream = state.planningEngine.streamPlanningPhase(
            planningPhase,
            apiKey: prepared.apiKey,
            configuration: configuration,
            conversation: prepared.conversation,
            baseInput: baseInput
        )

        return try await consumeLeaderPlanningStream(
            stream,
            planningPhase: planningPhase,
            prepared: prepared,
            execution: execution,
            initialState: HiddenLeaderStreamState(
                responseID: nil,
                lastSequenceNumber: nil,
                rawText: "",
                toolCalls: []
            )
        )
    }

    func recoverLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        existingTicket: AgentRunTicket,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentLeaderPlanningResult {
        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &execution.snapshot)
        persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)

        guard let responseID = existingTicket.responseID, !responseID.isEmpty else {
            throw AgentRunFailure.incomplete("Leader planning could not reconnect.")
        }

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
            persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)
            return state.planningEngine.parsePlanningResult(from: fetched.text, responseID: responseID)

        case .failed:
            throw AgentRunFailure.invalidResponse(
                fetched.errorMessage ?? "Leader planning failed."
            )

        case .incomplete:
            applyRecoveredLeaderPreview(
                outputText: fetched.text,
                planningPhase: planningPhase,
                execution: execution
            )
            throw AgentRunFailure.incomplete(
                fetched.errorMessage ?? "Leader planning was incomplete."
            )

        case .queued, .inProgress, .unknown:
            if let lastSequenceNumber = existingTicket.lastSequenceNumber {
                let stream = execution.service.streamRecovery(
                    responseId: responseID,
                    startingAfter: lastSequenceNumber,
                    apiKey: prepared.apiKey
                )
                return try await consumeLeaderPlanningStream(
                    stream,
                    planningPhase: planningPhase,
                    prepared: prepared,
                    execution: execution,
                    initialState: HiddenLeaderStreamState(
                        responseID: existingTicket.responseID,
                        lastSequenceNumber: existingTicket.lastSequenceNumber,
                        rawText: existingTicket.partialOutputText,
                        toolCalls: existingTicket.toolCalls
                    )
                )
            }

            return try await pollLeaderPlanningPhase(
                planningPhase,
                prepared: prepared,
                execution: execution,
                responseID: responseID,
                baseInput: baseInput
            )
        }
    }

    func pollLeaderPlanningPhase(
        _ planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        responseID: String,
        baseInput _: [ResponsesInputMessageDTO]
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
                persistCheckpointIfNeeded(execution, in: prepared.conversation, forceSave: true)
                return state.planningEngine.parsePlanningResult(from: fetched.text, responseID: responseID)

            case .failed:
                throw AgentRunFailure.invalidResponse(
                    fetched.errorMessage ?? "Leader planning failed."
                )

            case .incomplete:
                applyRecoveredLeaderPreview(
                    outputText: fetched.text,
                    planningPhase: planningPhase,
                    execution: execution
                )
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
}
