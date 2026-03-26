import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func handleLeaderPlanningEvent(
        _ event: StreamEvent,
        planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        configuration: AgentConversationConfiguration,
        streamState: inout HiddenLeaderStreamState
    ) -> HiddenLeaderStreamAction {
        switch event {
        case let .responseCreated(responseID):
            handleLeaderPlanningResponseCreated(
                responseID,
                planningPhase: planningPhase,
                prepared: prepared,
                execution: execution,
                configuration: configuration,
                streamState: &streamState
            )
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            execution.markProgress()
            return .none

        case let .sequenceUpdate(sequenceNumber):
            streamState.lastSequenceNumber = sequenceNumber
            updateLeaderTicket(
                execution: execution,
                conversation: prepared.conversation,
                phase: planningPhase.runPhase,
                responseID: streamState.responseID,
                lastSequenceNumber: sequenceNumber,
                rawText: streamState.rawText,
                toolCalls: streamState.toolCalls,
                forceSave: true
            )
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            execution.markProgress()
            return .none

        case let .textDelta(delta):
            streamState.rawText += delta
            refreshLeaderPlanningPreview(
                planningPhase: planningPhase,
                prepared: prepared,
                execution: execution,
                streamState: streamState
            )
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            execution.markProgress()
            return .none

        case let .replaceText(text):
            streamState.rawText = text
            refreshLeaderPlanningPreview(
                planningPhase: planningPhase,
                prepared: prepared,
                execution: execution,
                streamState: streamState
            )
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            execution.markProgress()
            return .none

        case .thinkingStarted:
            let summary = execution.snapshot.processSnapshot.leaderLiveSummary.isEmpty
                ? planningPhase.bootstrapSummary
                : execution.snapshot.processSnapshot.leaderLiveSummary
            AgentProcessProjector.updateLeaderLivePreview(
                status: "Reasoning",
                summary: summary,
                on: &execution.snapshot
            )
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            execution.markProgress()
            return .none

        case .thinkingFinished:
            AgentProcessProjector.updateLeaderLivePreview(
                status: planningPhase.bootstrapStatus,
                summary: execution.snapshot.processSnapshot.leaderLiveSummary,
                on: &execution.snapshot
            )
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            execution.markProgress()
            return .none

        case let .completed(text, _, _):
            streamState.rawText = text
            return .completed

        case let .incomplete(text, _, _, message):
            streamState.rawText = text
            refreshLeaderPlanningPreview(
                planningPhase: planningPhase,
                prepared: prepared,
                execution: execution,
                streamState: streamState,
                forceSave: true
            )
            return .failed(.incomplete(message ?? "Leader planning ended before completion."))

        case .connectionLost:
            return .failed(.connectionLost("Leader planning lost its connection."))

        case let .error(error):
            return .failed(.invalidResponse(error.localizedDescription))

        default:
            guard applyHiddenLeaderToolEvent(
                event,
                planningPhase: planningPhase,
                execution: execution,
                conversation: prepared.conversation,
                streamState: &streamState
            ) else {
                return .none
            }
            return .none
        }
    }

    func handleLeaderPlanningResponseCreated(
        _ responseID: String,
        planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        configuration: AgentConversationConfiguration,
        streamState: inout HiddenLeaderStreamState
    ) {
        streamState.responseID = responseID
        let checkpointBaseResponseID = streamState.checkpointBaseResponseID
            ?? execution.snapshot.ticket(for: .leader)?.checkpointBaseResponseID
        streamState.checkpointBaseResponseID = checkpointBaseResponseID
        updateRoleResponseID(responseID, for: .leader, in: prepared.conversation)
        updateTicket(
            AgentRunTicket(
                role: .leader,
                phase: planningPhase.runPhase,
                responseID: responseID,
                checkpointBaseResponseID: checkpointBaseResponseID,
                backgroundEligible: configuration.backgroundModeEnabled,
                partialOutputText: streamState.rawText,
                statusText: execution.snapshot.processSnapshot.leaderLiveStatus,
                summaryText: execution.snapshot.processSnapshot.leaderLiveSummary,
                toolCalls: streamState.toolCalls
            ),
            for: .leader,
            execution: execution,
            conversation: prepared.conversation,
            forceSave: true
        )
    }

    func refreshLeaderPlanningPreview(
        planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        streamState: HiddenLeaderStreamState,
        forceSave: Bool = false
    ) {
        applyRecoveredLeaderPreview(
            outputText: streamState.rawText,
            planningPhase: planningPhase,
            execution: execution
        )
        updateLeaderTicket(
            execution: execution,
            conversation: prepared.conversation,
            phase: planningPhase.runPhase,
            responseID: streamState.responseID,
            lastSequenceNumber: streamState.lastSequenceNumber,
            rawText: streamState.rawText,
            toolCalls: streamState.toolCalls,
            forceSave: forceSave
        )
    }

    func finalizeLeaderPlanningStream(
        planningPhase _: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        streamState: HiddenLeaderStreamState
    ) throws -> AgentLeaderPlanningResult {
        guard let responseID = streamState.responseID, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Leader planning response id is missing.")
        }

        AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        let result = state.planningEngine.parsePlanningResult(
            from: streamState.rawText,
            responseID: responseID
        )
        clearTicket(
            for: .leader,
            execution: execution,
            conversation: prepared.conversation,
            forceSave: true
        )
        return result
    }
}
