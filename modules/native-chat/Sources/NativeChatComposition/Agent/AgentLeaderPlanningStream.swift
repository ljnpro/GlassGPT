import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

struct HiddenLeaderStreamState {
    var responseID: String?
    var lastSequenceNumber: Int?
    var rawText: String
    var toolCalls: [ToolCallInfo]
}

enum HiddenLeaderStreamAction {
    case none
    case completed
    case failed(AgentRunFailure)
}

extension AgentRunCoordinator {
    func consumeLeaderPlanningStream(
        _ stream: AsyncStream<StreamEvent>,
        planningPhase: AgentPlanningEngine.PlanningPhase,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        initialState: HiddenLeaderStreamState
    ) async throws -> AgentLeaderPlanningResult {
        let configuration = frozenRunConfiguration(for: execution, conversation: prepared.conversation)
        var streamState = initialState
        applyRecoveredLeaderPreview(
            outputText: streamState.rawText,
            planningPhase: planningPhase,
            execution: execution
        )

        for await event in stream {
            try Task.checkCancellation()
            let action = handleLeaderPlanningEvent(
                event,
                planningPhase: planningPhase,
                prepared: prepared,
                execution: execution,
                configuration: configuration,
                streamState: &streamState
            )
            switch action {
            case .none, .completed:
                continue
            case let .failed(error):
                throw error
            }
        }

        return try finalizeLeaderPlanningStream(
            planningPhase: planningPhase,
            prepared: prepared,
            execution: execution,
            streamState: streamState
        )
    }

    func applyRecoveredLeaderPreview(
        outputText: String,
        planningPhase: AgentPlanningEngine.PlanningPhase,
        execution: AgentExecutionState
    ) {
        let preview = AgentTaggedOutputParser.parseLeaderDirectivePreview(from: outputText)
        let summary = preview.focus ?? preview.decisionNote ?? planningPhase.bootstrapSummary
        AgentProcessProjector.updateLeaderLivePreview(
            status: preview.status ?? planningPhase.bootstrapStatus,
            summary: summary,
            on: &execution.snapshot
        )
        if let focus = preview.focus, !focus.isEmpty {
            execution.snapshot.processSnapshot.currentFocus = focus
        }
        if !preview.plan.isEmpty {
            execution.snapshot.processSnapshot.plan = preview.plan
        }
    }

    func updateLeaderTicket(
        execution: AgentExecutionState,
        conversation: Conversation,
        phase: AgentRunPhase,
        responseID: String?,
        lastSequenceNumber: Int?,
        rawText: String,
        toolCalls: [ToolCallInfo],
        forceSave: Bool
    ) {
        updateTicket(
            AgentRunTicket(
                role: .leader,
                phase: phase,
                responseID: responseID,
                lastSequenceNumber: lastSequenceNumber,
                backgroundEligible: frozenRunConfiguration(
                    for: execution,
                    conversation: conversation
                ).backgroundModeEnabled,
                partialOutputText: rawText,
                statusText: execution.snapshot.processSnapshot.leaderLiveStatus,
                summaryText: execution.snapshot.processSnapshot.leaderLiveSummary,
                toolCalls: toolCalls
            ),
            for: .leader,
            execution: execution,
            conversation: conversation,
            forceSave: forceSave
        )
    }
}
