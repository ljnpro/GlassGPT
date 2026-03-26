import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

struct AgentWorkerStreamState {
    var responseID: String?
    var rawText = ""
    var toolCalls: [ToolCallInfo] = []
    var citations: [URLCitation] = []
}

private enum AgentWorkerStreamAction {
    case none
    case refreshPreview
    case persistPreview(forceSave: Bool)
    case completed
    case failed(AgentRunFailure)
}

extension AgentWorkerRuntime {
    func consumeTaskStream(
        _ stream: AsyncStream<StreamEvent>,
        task: AgentTask,
        role: AgentRole,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        initialState: AgentWorkerStreamState
    ) async throws -> AgentWorkerExecutionResult {
        var streamState = initialState
        var latestTask = task

        for await event in stream {
            try Task.checkCancellation()
            let action = handleStreamEvent(
                event,
                task: task,
                role: role,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                streamState: &streamState,
                latestTask: &latestTask
            )
            switch action {
            case .none:
                continue
            case .refreshPreview:
                latestTask = syncPreview(
                    for: task,
                    rawText: streamState.rawText,
                    execution: execution,
                    conversation: conversation
                )
            case let .persistPreview(forceSave):
                persistTicketPreview(
                    role: role,
                    taskID: task.id,
                    streamState: streamState,
                    latestTask: latestTask,
                    configuration: configuration,
                    execution: execution,
                    conversation: conversation,
                    forceSave: forceSave
                )
            case .completed:
                continue
            case let .failed(error):
                throw error
            }
        }

        return try finalizeTaskStream(
            role: role,
            task: latestTask,
            execution: execution,
            conversation: conversation,
            streamState: streamState
        )
    }

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
        return AgentWorkerExecutionResult(task: finishedTask, responseID: responseID)
    }
}

private extension AgentWorkerRuntime {
    func handleStreamEvent(
        _ event: StreamEvent,
        task: AgentTask,
        role: AgentRole,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        streamState: inout AgentWorkerStreamState,
        latestTask: inout AgentTask
    ) -> AgentWorkerStreamAction {
        switch event {
        case let .responseCreated(responseID):
            handleResponseCreated(
                responseID,
                role: role,
                task: task,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                streamState: &streamState,
                latestTask: latestTask
            )
            return .none

        case let .sequenceUpdate(sequenceNumber):
            handleSequenceUpdate(
                sequenceNumber,
                role: role,
                task: task,
                configuration: configuration,
                conversation: conversation,
                execution: execution,
                streamState: streamState,
                latestTask: latestTask
            )
            return .none

        case let .textDelta(delta):
            streamState.rawText += delta
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            return .refreshPreview

        case let .replaceText(text):
            streamState.rawText = text
            AgentProcessProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            return .refreshPreview

        case let .completed(text, _, _):
            streamState.rawText = text
            return .completed

        case let .incomplete(text, _, _, message):
            streamState.rawText = text
            latestTask = syncPreview(
                for: task,
                rawText: streamState.rawText,
                execution: execution,
                conversation: conversation
            )
            persistTicketPreview(
                role: role,
                taskID: task.id,
                streamState: streamState,
                latestTask: latestTask,
                configuration: configuration,
                execution: execution,
                conversation: conversation,
                forceSave: true
            )
            return .failed(.incomplete(message ?? "Worker task ended before completion."))

        case .connectionLost:
            return .failed(.incomplete("Worker task lost its connection."))

        case let .error(error):
            return .failed(.invalidResponse(error.localizedDescription))

        case let .annotationAdded(annotation):
            if !streamState.citations.contains(annotation) {
                streamState.citations.append(annotation)
            }
            return .none

        default:
            applyToolEvent(event, streamState: &streamState)
            return .persistPreview(forceSave: false)
        }
    }
}
