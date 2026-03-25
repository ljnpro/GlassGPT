import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

struct AgentWorkerExecutionResult {
    let task: AgentTask
    let responseID: String
}

private struct AgentWorkerStreamState {
    var responseID: String?
    var rawText = ""
    var toolCalls: [ToolCallInfo] = []
    var citations: [URLCitation] = []
}

@MainActor
final class AgentWorkerRuntime {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func runTask(
        _ task: AgentTask,
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        currentFocus: String,
        decisionSummary: String
    ) async throws -> AgentWorkerExecutionResult {
        guard let role = task.owner.role else {
            throw AgentRunFailure.invalidResponse("Leader cannot be used as a worker owner.")
        }

        let stream = state.serviceFactory().streamResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.workerTaskInput(
                baseInput: baseInput,
                task: task,
                currentFocus: currentFocus,
                priorDecisionSummary: decisionSummary
            ),
            instructions: AgentPromptBuilder.workerTaskInstructions(
                for: task.owner,
                toolPolicy: task.toolPolicy
            ),
            previousResponseID: conversation.agentConversationState?.responseID(for: role),
            reasoningEffort: configuration.workerReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: task.toolPolicy == .enabled ? OpenAIRequestFactory.defaultChatTools() : []
        )

        var streamState = AgentWorkerStreamState()
        var latestTask = task

        for await event in stream {
            try Task.checkCancellation()
            switch event {
            case let .responseCreated(responseID):
                streamState.responseID = responseID

            case let .textDelta(delta):
                streamState.rawText += delta
                latestTask = syncPreview(
                    for: task,
                    rawText: streamState.rawText,
                    execution: execution,
                    conversation: conversation
                )

            case let .replaceText(text):
                streamState.rawText = text
                latestTask = syncPreview(
                    for: task,
                    rawText: streamState.rawText,
                    execution: execution,
                    conversation: conversation
                )

            case let .completed(text, _, _):
                streamState.rawText = text

            case let .incomplete(text, _, _, message):
                streamState.rawText = text
                latestTask = syncPreview(
                    for: task,
                    rawText: streamState.rawText,
                    execution: execution,
                    conversation: conversation
                )
                throw AgentRunFailure.incomplete(message ?? "Worker task ended before completion.")

            case .connectionLost:
                throw AgentRunFailure.incomplete("Worker task lost its connection.")

            case let .error(error):
                throw AgentRunFailure.invalidResponse(error.localizedDescription)

            case let .annotationAdded(annotation):
                if !streamState.citations.contains(annotation) {
                    streamState.citations.append(annotation)
                }

            default:
                applyToolEvent(
                    event,
                    streamState: &streamState
                )
            }
        }

        guard let responseID = streamState.responseID, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Worker response id is missing.")
        }

        let parsed = AgentTaggedOutputParser.parseWorkerTaskResult(
            from: streamState.rawText
        )
        var finishedTask = latestTask
        finishedTask.result = AgentTaskResult(
            summary: parsed.summary,
            evidence: parsed.evidence,
            confidence: parsed.confidence,
            risks: parsed.risks,
            followUpRecommendations: parsed.followUps,
            toolCalls: streamState.toolCalls,
            citations: streamState.citations
        )
        finishedTask.resultSummary = AgentSummaryFormatter.summarize(parsed.summary, maxLength: 150)
        finishedTask.completedAt = .now
        return AgentWorkerExecutionResult(task: finishedTask, responseID: responseID)
    }

    private func syncPreview(
        for task: AgentTask,
        rawText: String,
        execution: AgentExecutionState,
        conversation: Conversation
    ) -> AgentTask {
        let preview = AgentTaggedOutputParser.parseWorkerTaskPreview(from: rawText)
        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: AgentSummaryFormatter.summarize(preview.status ?? "Running", maxLength: 40),
            summary: AgentSummaryFormatter.summarize(preview.summary ?? task.goal, maxLength: 140),
            evidence: AgentSummaryFormatter.summarizeBullets(preview.evidence, maxItems: 1, maxLength: 88),
            confidence: preview.confidence,
            risks: AgentSummaryFormatter.summarizeBullets(preview.risks, maxItems: 1, maxLength: 88),
            on: &execution.snapshot
        )
        state.runCoordinator.persistSnapshot(
            execution,
            in: conversation,
            save: currentAgentConfiguration(for: conversation).backgroundModeEnabled
        )
        return execution.snapshot.processSnapshot.tasks.first(where: { $0.id == task.id }) ?? task
    }

    private func currentAgentConfiguration(for conversation: Conversation) -> AgentConversationConfiguration {
        conversation.agentConversationState?.configuration ?? AgentConversationConfiguration()
    }

    private func applyToolEvent(
        _ event: StreamEvent,
        streamState: inout AgentWorkerStreamState
    ) {
        switch event {
        case let .webSearchStarted(id):
            startToolCall(id: id, type: .webSearch, in: &streamState)
        case let .webSearchSearching(id):
            setToolCallStatus(id: id, status: .searching, in: &streamState)
        case let .webSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, in: &streamState)
        case let .codeInterpreterStarted(id):
            startToolCall(id: id, type: .codeInterpreter, in: &streamState)
        case let .codeInterpreterInterpreting(id):
            setToolCallStatus(id: id, status: .interpreting, in: &streamState)
        case let .codeInterpreterCodeDelta(id, delta):
            appendToolCode(id: id, delta: delta, in: &streamState)
        case let .codeInterpreterCodeDone(id, code):
            setToolCode(id: id, code: code, in: &streamState)
        case let .codeInterpreterCompleted(id):
            setToolCallStatus(id: id, status: .completed, in: &streamState)
        case let .fileSearchStarted(id):
            startToolCall(id: id, type: .fileSearch, in: &streamState)
        case let .fileSearchSearching(id):
            setToolCallStatus(id: id, status: .fileSearching, in: &streamState)
        case let .fileSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, in: &streamState)
        default:
            break
        }
    }

    private func startToolCall(
        id: String,
        type: ToolCallType,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard !streamState.toolCalls.contains(where: { $0.id == id }) else { return }
        streamState.toolCalls.append(
            ToolCallInfo(id: id, type: type, status: .inProgress)
        )
    }

    private func setToolCallStatus(
        id: String,
        status: ToolCallStatus,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard let index = streamState.toolCalls.firstIndex(where: { $0.id == id }) else { return }
        streamState.toolCalls[index].status = status
    }

    private func appendToolCode(
        id: String,
        delta: String,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard let index = streamState.toolCalls.firstIndex(where: { $0.id == id }) else { return }
        streamState.toolCalls[index].code = (streamState.toolCalls[index].code ?? "") + delta
    }

    private func setToolCode(
        id: String,
        code: String,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard let index = streamState.toolCalls.firstIndex(where: { $0.id == id }) else { return }
        streamState.toolCalls[index].code = code
    }
}
