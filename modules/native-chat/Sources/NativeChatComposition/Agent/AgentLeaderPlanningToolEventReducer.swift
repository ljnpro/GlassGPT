import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func applyHiddenLeaderToolEvent(
        _ event: StreamEvent,
        planningPhase: AgentPlanningEngine.PlanningPhase,
        execution: AgentExecutionState,
        conversation: Conversation,
        streamState: inout HiddenLeaderStreamState
    ) -> Bool {
        let status: String?

        switch event {
        case let .webSearchStarted(id):
            streamState.toolCalls.append(
                ToolCallInfo(id: id, type: .webSearch, status: .inProgress)
            )
            status = "Searching the web"
        case let .webSearchSearching(id):
            setHiddenLeaderToolCallStatus(id: id, status: .searching, in: &streamState.toolCalls)
            status = "Searching the web"
        case let .webSearchCompleted(id):
            setHiddenLeaderToolCallStatus(id: id, status: .completed, in: &streamState.toolCalls)
            status = planningPhase.bootstrapStatus
        case let .codeInterpreterStarted(id):
            streamState.toolCalls.append(
                ToolCallInfo(id: id, type: .codeInterpreter, status: .inProgress)
            )
            status = "Running code"
        case let .codeInterpreterInterpreting(id):
            setHiddenLeaderToolCallStatus(id: id, status: .interpreting, in: &streamState.toolCalls)
            status = "Running code"
        case let .codeInterpreterCompleted(id):
            setHiddenLeaderToolCallStatus(id: id, status: .completed, in: &streamState.toolCalls)
            status = planningPhase.bootstrapStatus
        case let .fileSearchStarted(id):
            streamState.toolCalls.append(
                ToolCallInfo(id: id, type: .fileSearch, status: .inProgress)
            )
            status = "Searching files"
        case let .fileSearchSearching(id):
            setHiddenLeaderToolCallStatus(id: id, status: .fileSearching, in: &streamState.toolCalls)
            status = "Searching files"
        case let .fileSearchCompleted(id):
            setHiddenLeaderToolCallStatus(id: id, status: .completed, in: &streamState.toolCalls)
            status = planningPhase.bootstrapStatus
        default:
            return false
        }

        AgentProcessProjector.updateLeaderLivePreview(
            status: status,
            summary: execution.snapshot.processSnapshot.leaderLiveSummary,
            on: &execution.snapshot
        )
        AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        execution.markProgress()
        updateLeaderTicket(
            execution: execution,
            conversation: conversation,
            phase: planningPhase.runPhase,
            responseID: streamState.responseID,
            lastSequenceNumber: streamState.lastSequenceNumber,
            rawText: streamState.rawText,
            toolCalls: streamState.toolCalls,
            forceSave: false
        )
        return true
    }

    func setHiddenLeaderToolCallStatus(
        id: String,
        status: ToolCallStatus,
        in toolCalls: inout [ToolCallInfo]
    ) {
        guard let index = toolCalls.firstIndex(where: { $0.id == id }) else {
            return
        }
        toolCalls[index].status = status
    }
}
