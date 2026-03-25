import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func applyVisibleStreamEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message
    ) throws {
        if try applyLifecycleEvent(
            event,
            execution: execution,
            conversation: conversation,
            draft: draft
        ) {
            syncVisibleStateIfNeeded(execution, in: conversation)
            return
        }
        if applyToolEvent(event, execution: execution, conversation: conversation, draft: draft) {
            syncVisibleStateIfNeeded(execution, in: conversation)
            return
        }
        applyAnnotationEvent(event, execution: execution, conversation: conversation, draft: draft)
        syncVisibleStateIfNeeded(execution, in: conversation)
    }

    private func applyLifecycleEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message
    ) throws -> Bool {
        switch event {
        case let .textDelta(delta):
            execution.snapshot.currentStreamingText += delta
            draft.content = execution.snapshot.currentStreamingText
        case let .replaceText(text):
            execution.snapshot.currentStreamingText = text
            draft.content = text
        case .thinkingStarted:
            execution.snapshot.isThinking = true
        case let .thinkingDelta(delta):
            execution.snapshot.isThinking = true
            execution.snapshot.currentThinkingText += delta
            draft.thinking = execution.snapshot.currentThinkingText
        case .thinkingFinished:
            execution.snapshot.isThinking = false
        case let .responseCreated(responseID):
            updateRoleResponseID(responseID, for: .leader, in: conversation)
            draft.responseId = responseID
            persistSnapshot(execution, in: conversation)
        case let .sequenceUpdate(sequenceNumber):
            draft.lastSequenceNumber = sequenceNumber
        case let .completed(text, thinking, fileAnnotations):
            applyCompletionSnapshot(
                text: text,
                thinking: thinking,
                fileAnnotations: fileAnnotations,
                execution: execution,
                draft: draft
            )
            persistSnapshot(execution, in: conversation)
        case let .incomplete(text, thinking, fileAnnotations, message):
            applyCompletionSnapshot(
                text: text,
                thinking: thinking,
                fileAnnotations: fileAnnotations,
                execution: execution,
                draft: draft
            )
            persistSnapshot(execution, in: conversation)
            throw AgentRunFailure.incomplete(message ?? "Agent synthesis was incomplete.")
        case .connectionLost:
            throw AgentRunFailure.incomplete("Agent synthesis lost its connection.")
        case let .error(error):
            throw AgentRunFailure.invalidResponse(error.localizedDescription)
        default:
            return false
        }

        execution.snapshot.updatedAt = .now
        return true
    }

    private func applyToolEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message
    ) -> Bool {
        switch event {
        case let .webSearchStarted(id):
            startToolCall(id: id, type: .webSearch, execution: execution, draft: draft)
        case let .webSearchSearching(id):
            setToolCallStatus(id: id, status: .searching, execution: execution, draft: draft)
        case let .webSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
        case let .codeInterpreterStarted(id):
            startToolCall(id: id, type: .codeInterpreter, execution: execution, draft: draft)
        case let .codeInterpreterInterpreting(id):
            setToolCallStatus(id: id, status: .interpreting, execution: execution, draft: draft)
        case let .codeInterpreterCodeDelta(id, delta):
            appendToolCode(id: id, delta: delta, execution: execution, draft: draft)
        case let .codeInterpreterCodeDone(id, code):
            setToolCode(id: id, code: code, execution: execution, draft: draft)
        case let .codeInterpreterCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
        case let .fileSearchStarted(id):
            startToolCall(id: id, type: .fileSearch, execution: execution, draft: draft)
        case let .fileSearchSearching(id):
            setToolCallStatus(id: id, status: .fileSearching, execution: execution, draft: draft)
        case let .fileSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
        default:
            return false
        }

        execution.snapshot.updatedAt = .now
        if resolvedBackgroundPersistence(for: conversation) {
            persistSnapshot(execution, in: conversation, save: false)
        }
        return true
    }

    private func applyAnnotationEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message
    ) {
        switch event {
        case let .annotationAdded(annotation):
            execution.snapshot.liveCitations.append(annotation)
            draft.annotations = execution.snapshot.liveCitations
        case let .filePathAnnotationAdded(annotation):
            execution.snapshot.liveFilePathAnnotations.append(annotation)
            draft.filePathAnnotations = execution.snapshot.liveFilePathAnnotations
        default:
            break
        }

        execution.snapshot.updatedAt = .now
        if resolvedBackgroundPersistence(for: conversation) {
            persistSnapshot(execution, in: conversation, save: false)
        }
    }

    private func applyCompletionSnapshot(
        text: String,
        thinking: String?,
        fileAnnotations: [FilePathAnnotation]?,
        execution: AgentExecutionState,
        draft: Message
    ) {
        execution.snapshot.currentStreamingText = text
        execution.snapshot.isStreaming = false
        execution.snapshot.isThinking = false
        draft.content = text
        if let thinking {
            execution.snapshot.currentThinkingText = thinking
            draft.thinking = thinking
        }
        if let fileAnnotations {
            execution.snapshot.liveFilePathAnnotations = fileAnnotations
            draft.filePathAnnotations = fileAnnotations
        }
    }

    private func startToolCall(
        id: String,
        type: ToolCallType,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard !execution.snapshot.activeToolCalls.contains(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls.append(
            ToolCallInfo(
                id: id,
                type: type,
                status: .inProgress
            )
        )
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    private func setToolCallStatus(
        id: String,
        status: ToolCallStatus,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard let index = execution.snapshot.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls[index].status = status
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    private func appendToolCode(
        id: String,
        delta: String,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard let index = execution.snapshot.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls[index].code = (execution.snapshot.activeToolCalls[index].code ?? "") + delta
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    private func setToolCode(
        id: String,
        code: String,
        execution: AgentExecutionState,
        draft: Message
    ) {
        guard let index = execution.snapshot.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        execution.snapshot.activeToolCalls[index].code = code
        draft.toolCalls = execution.snapshot.activeToolCalls
    }

    private func resolvedBackgroundPersistence(for conversation: Conversation) -> Bool {
        currentAgentState(for: conversation).configuration.backgroundModeEnabled
    }
}
