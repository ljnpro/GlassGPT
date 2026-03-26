import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

@MainActor
extension AgentVisibleSynthesisEventApplier {
    static func refreshVisibleLeaderWritingPreview(
        execution: AgentExecutionState
    ) {
        let status = execution.snapshot.activeToolCalls.contains(where: { $0.status != .completed })
            ? "Waiting for tools"
            : "Writing final answer"
        updateVisibleLeaderPreview(
            status: status,
            summary: "Writing final answer from accepted findings.",
            execution: execution
        )
    }

    static func updateVisibleLeaderPreview(
        status: String,
        summary: String,
        execution: AgentExecutionState
    ) {
        AgentProcessProjector.updateLeaderLivePreview(
            status: status,
            summary: summary,
            on: &execution.snapshot
        )
    }

    static func startToolCall(
        id: String,
        type: ToolCallType,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard !execution.snapshot.activeToolCalls.contains(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls.append(
            ToolCallInfo(id: id, type: type, status: .inProgress)
        )
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    static func setToolCallStatus(
        id: String,
        status: ToolCallStatus,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard let index = execution.snapshot.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls[index].status = status
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    static func appendToolCode(
        id: String,
        delta: String,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard let index = execution.snapshot.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        let currentCode = execution.snapshot.activeToolCalls[index].code ?? ""
        execution.snapshot.activeToolCalls[index].code = currentCode + delta
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    static func setToolCode(
        id: String,
        code: String,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard let index = execution.snapshot.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls[index].code = code
        draft.toolCalls = execution.snapshot.activeToolCalls
    }
}
