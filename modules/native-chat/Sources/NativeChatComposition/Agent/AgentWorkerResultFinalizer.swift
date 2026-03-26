import ChatDomain
import ChatPersistenceSwiftData

extension AgentWorkerRuntime {
    func finishRecoveredTask(
        _ task: AgentTask,
        role: AgentRole,
        rawText: String,
        responseID: String,
        toolCalls: [ToolCallInfo],
        citations: [URLCitation],
        execution: AgentExecutionState,
        conversation: Conversation
    ) -> AgentWorkerExecutionResult {
        let parsed = AgentTaggedOutputParser.parseWorkerTaskResult(from: rawText)
        var finishedTask = syncPreview(
            for: task,
            rawText: rawText,
            execution: execution,
            conversation: conversation
        )
        finishedTask.result = makeTaskResult(
            parsed: parsed,
            toolCalls: toolCalls,
            citations: citations
        )
        finishedTask.resultSummary = AgentSummaryFormatter.summarize(parsed.summary, maxLength: 150)
        finishedTask.completedAt = .now
        state.runCoordinator.clearTicket(
            for: role,
            execution: execution,
            conversation: conversation,
            forceSave: true
        )
        AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        execution.markProgress()
        return AgentWorkerExecutionResult(task: finishedTask, responseID: responseID)
    }
}
