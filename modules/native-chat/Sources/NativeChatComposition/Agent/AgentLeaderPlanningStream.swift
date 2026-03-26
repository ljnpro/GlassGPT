import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

struct HiddenLeaderStreamState {
    var responseID: String?
    var checkpointBaseResponseID: String?
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
        initialState: HiddenLeaderStreamState,
        finalizeWhenStreamEnds: Bool = true
    ) async throws -> AgentLeaderPlanningResult? {
        let configuration = frozenRunConfiguration(for: execution, conversation: prepared.conversation)
        var streamState = initialState
        var didReceiveTerminalCompletion = false
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
                if case .completed = action {
                    didReceiveTerminalCompletion = true
                }
                continue
            case let .failed(error):
                throw error
            }
        }

        guard finalizeWhenStreamEnds || didReceiveTerminalCompletion else {
            return nil
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
        let retainedTasks = execution.snapshot.processSnapshot.tasks.filter { task in
            guard let role = task.owner.role else { return true }
            if task.status == .completed || task.status == .failed || task.status == .blocked || task.result != nil {
                return true
            }
            return execution.snapshot.ticket(for: role)?.responseID?.isEmpty == false
        }
        var refreshedTasks = retainedTasks
        for task in preview.tasks where refreshedTasks.contains(where: { $0.owner == task.owner && $0.title == task.title }) == false {
            refreshedTasks.append(task)
        }
        execution.snapshot.processSnapshot.tasks = refreshedTasks
        execution.snapshot.processSnapshot.activeTaskIDs = refreshedTasks
            .filter { $0.status == .running }
            .map(\.id)
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
                checkpointBaseResponseID: execution.snapshot.ticket(for: .leader)?.checkpointBaseResponseID,
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
