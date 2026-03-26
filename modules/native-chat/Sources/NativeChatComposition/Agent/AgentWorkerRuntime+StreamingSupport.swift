import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentWorkerRuntime {
    func handleResponseCreated(
        _ responseID: String,
        role: AgentRole,
        task: AgentTask,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        streamState: inout AgentWorkerStreamState,
        latestTask: AgentTask
    ) {
        streamState.responseID = responseID
        AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        state.runCoordinator.updateTicket(
            AgentRunTicket(
                role: role,
                phase: .workerWave,
                taskID: task.id,
                responseID: responseID,
                checkpointBaseResponseID: execution.snapshot.ticket(for: role)?.checkpointBaseResponseID,
                backgroundEligible: configuration.backgroundModeEnabled,
                partialOutputText: streamState.rawText,
                statusText: latestTask.displayStatusText,
                summaryText: latestTask.displaySummary,
                toolCalls: streamState.toolCalls
            ),
            for: role,
            execution: execution,
            conversation: conversation,
            forceSave: true
        )
    }

    func handleSequenceUpdate(
        _ sequenceNumber: Int,
        role: AgentRole,
        task: AgentTask,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        streamState: AgentWorkerStreamState,
        latestTask: AgentTask
    ) {
        var ticket = execution.snapshot.ticket(for: role) ?? AgentRunTicket(
            role: role,
            phase: .workerWave,
            taskID: task.id,
            backgroundEligible: configuration.backgroundModeEnabled
        )
        ticket.taskID = task.id
        ticket.responseID = streamState.responseID
        ticket.lastSequenceNumber = sequenceNumber
        ticket.partialOutputText = streamState.rawText
        ticket.statusText = latestTask.displayStatusText
        ticket.summaryText = latestTask.displaySummary
        ticket.toolCalls = streamState.toolCalls
        state.runCoordinator.updateTicket(
            ticket,
            for: role,
            execution: execution,
            conversation: conversation,
            forceSave: true
        )
    }

    func finalizeTaskStream(
        role: AgentRole,
        task: AgentTask,
        execution: AgentExecutionState,
        conversation: Conversation,
        streamState: AgentWorkerStreamState
    ) throws -> AgentWorkerExecutionResult {
        guard let responseID = streamState.responseID, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Worker response id is missing.")
        }

        let parsed = AgentTaggedOutputParser.parseWorkerTaskResult(from: streamState.rawText)
        var finishedTask = task
        finishedTask.result = makeTaskResult(
            parsed: parsed,
            toolCalls: streamState.toolCalls,
            citations: streamState.citations
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
        return AgentWorkerExecutionResult(task: finishedTask, responseID: responseID)
    }

    func syncPreview(
        for task: AgentTask,
        rawText: String,
        execution: AgentExecutionState,
        conversation: Conversation
    ) -> AgentTask {
        let preview = AgentTaggedOutputParser.parseWorkerTaskPreview(from: rawText)
        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: AgentSummaryFormatter.summarize(preview.status ?? "Running", maxLength: 32),
            summary: AgentSummaryFormatter.summarize(preview.summary ?? task.goal, maxLength: 96),
            evidence: AgentSummaryFormatter.summarizeBullets(
                preview.evidence,
                maxItems: 1,
                maxLength: 72
            ),
            confidence: preview.confidence,
            risks: AgentSummaryFormatter.summarizeBullets(
                preview.risks,
                maxItems: 1,
                maxLength: 72
            ),
            on: &execution.snapshot
        )
        state.runCoordinator.persistCheckpointIfNeeded(execution, in: conversation)
        return execution.snapshot.processSnapshot.tasks.first(where: { $0.id == task.id }) ?? task
    }

    func persistTicketPreview(
        role: AgentRole,
        taskID: String,
        streamState: AgentWorkerStreamState,
        latestTask: AgentTask,
        configuration: AgentConversationConfiguration,
        execution: AgentExecutionState,
        conversation: Conversation,
        forceSave: Bool
    ) {
        let persistedSequence = execution.snapshot.ticket(for: role)?.lastSequenceNumber
        state.runCoordinator.updateTicket(
            AgentRunTicket(
                role: role,
                phase: .workerWave,
                taskID: taskID,
                responseID: streamState.responseID,
                checkpointBaseResponseID: execution.snapshot.ticket(for: role)?.checkpointBaseResponseID,
                lastSequenceNumber: persistedSequence,
                backgroundEligible: configuration.backgroundModeEnabled,
                partialOutputText: streamState.rawText,
                statusText: latestTask.displayStatusText,
                summaryText: latestTask.displaySummary,
                toolCalls: streamState.toolCalls
            ),
            for: role,
            execution: execution,
            conversation: conversation,
            forceSave: forceSave
        )
    }

    func makeTaskResult(
        parsed: AgentTaggedOutputParser.WorkerTaskResult,
        toolCalls: [ToolCallInfo],
        citations: [URLCitation]
    ) -> AgentTaskResult {
        AgentTaskResult(
            summary: parsed.summary,
            evidence: parsed.evidence,
            confidence: parsed.confidence,
            risks: parsed.risks,
            followUpRecommendations: parsed.followUps,
            toolCalls: toolCalls,
            citations: citations
        )
    }
}
