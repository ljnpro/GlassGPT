import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

@MainActor
enum AgentVisibleSynthesisEventApplier {
    static func apply(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message,
        coordinator: AgentRunCoordinator
    ) throws {
        if try applyLifecycleEvent(
            event,
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: coordinator
        ) {
            return
        }
        if applyToolEvent(
            event,
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: coordinator
        ) {
            return
        }
        applyAnnotationEvent(
            event,
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: coordinator
        )
    }

    private static func applyLifecycleEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message,
        coordinator: AgentRunCoordinator
    ) throws -> Bool {
        switch event {
        case let .textDelta(delta):
            execution.snapshot.currentStreamingText += delta
            draft.content = execution.snapshot.currentStreamingText
            refreshVisibleLeaderWritingPreview(execution: execution)
        case let .replaceText(text):
            execution.snapshot.currentStreamingText = text
            draft.content = text
            refreshVisibleLeaderWritingPreview(execution: execution)
        case .thinkingStarted:
            execution.snapshot.isThinking = true
            updateVisibleLeaderPreview(
                status: "Reasoning",
                summary: "Reasoning over accepted findings before final output.",
                execution: execution
            )
        case let .thinkingDelta(delta):
            execution.snapshot.isThinking = true
            execution.snapshot.currentThinkingText += delta
            draft.thinking = execution.snapshot.currentThinkingText
            updateVisibleLeaderPreview(
                status: "Reasoning",
                summary: "Reasoning over accepted findings before final output.",
                execution: execution
            )
        case .thinkingFinished:
            execution.snapshot.isThinking = false
            refreshVisibleLeaderWritingPreview(execution: execution)
        case let .responseCreated(responseID):
            coordinator.updateRoleResponseID(responseID, for: .leader, in: conversation)
            draft.responseId = responseID
            persistVisibleLeaderTicket(
                responseID: responseID,
                sequenceNumber: nil,
                execution: execution,
                conversation: conversation,
                coordinator: coordinator,
                forceSave: true
            )
            coordinator.persistSnapshot(execution, in: conversation)
        case let .sequenceUpdate(sequenceNumber):
            draft.lastSequenceNumber = sequenceNumber
            persistVisibleLeaderTicket(
                responseID: draft.responseId,
                sequenceNumber: sequenceNumber,
                execution: execution,
                conversation: conversation,
                coordinator: coordinator,
                forceSave: execution.snapshot.runConfiguration.backgroundModeEnabled
            )
        case let .completed(text, thinking, fileAnnotations):
            try finishVisibleLifecycle(
                text: text,
                thinking: thinking,
                fileAnnotations: fileAnnotations,
                execution: execution,
                conversation: conversation,
                draft: draft,
                coordinator: coordinator,
                incompleteMessage: nil
            )
        case let .incomplete(text, thinking, fileAnnotations, message):
            try finishVisibleLifecycle(
                text: text,
                thinking: thinking,
                fileAnnotations: fileAnnotations,
                execution: execution,
                conversation: conversation,
                draft: draft,
                coordinator: coordinator,
                incompleteMessage: message ?? "Agent synthesis was incomplete."
            )
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

    private static func applyToolEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message,
        coordinator: AgentRunCoordinator
    ) -> Bool {
        switch event {
        case let .webSearchStarted(id):
            startToolCall(id: id, type: .webSearch, execution: execution, draft: draft)
            updateVisibleLeaderPreview(
                status: "Searching the web",
                summary: "Checking supporting evidence before the final answer.",
                execution: execution
            )
        case let .webSearchSearching(id):
            setToolCallStatus(id: id, status: .searching, execution: execution, draft: draft)
            updateVisibleLeaderPreview(
                status: "Searching the web",
                summary: "Checking supporting evidence before the final answer.",
                execution: execution
            )
        case let .webSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
            refreshVisibleLeaderWritingPreview(execution: execution)
        case let .codeInterpreterStarted(id):
            startToolCall(id: id, type: .codeInterpreter, execution: execution, draft: draft)
            updateVisibleLeaderPreview(
                status: "Running code",
                summary: "Validating the final answer with code execution.",
                execution: execution
            )
        case let .codeInterpreterInterpreting(id):
            setToolCallStatus(id: id, status: .interpreting, execution: execution, draft: draft)
            updateVisibleLeaderPreview(
                status: "Running code",
                summary: "Validating the final answer with code execution.",
                execution: execution
            )
        case let .codeInterpreterCodeDelta(id, delta):
            appendToolCode(id: id, delta: delta, execution: execution, draft: draft)
        case let .codeInterpreterCodeDone(id, code):
            setToolCode(id: id, code: code, execution: execution, draft: draft)
        case let .codeInterpreterCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
            refreshVisibleLeaderWritingPreview(execution: execution)
        case let .fileSearchStarted(id):
            startToolCall(id: id, type: .fileSearch, execution: execution, draft: draft)
            updateVisibleLeaderPreview(
                status: "Searching files",
                summary: "Checking supporting files before the final answer.",
                execution: execution
            )
        case let .fileSearchSearching(id):
            setToolCallStatus(id: id, status: .fileSearching, execution: execution, draft: draft)
            updateVisibleLeaderPreview(
                status: "Searching files",
                summary: "Checking supporting files before the final answer.",
                execution: execution
            )
        case let .fileSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
            refreshVisibleLeaderWritingPreview(execution: execution)
        default:
            return false
        }

        execution.snapshot.updatedAt = .now
        if resolvedBackgroundPersistence(for: conversation, coordinator: coordinator) {
            coordinator.persistSnapshot(execution, in: conversation, save: false)
        }
        return true
    }

    private static func applyAnnotationEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message,
        coordinator: AgentRunCoordinator
    ) {
        switch event {
        case let .annotationAdded(annotation):
            execution.snapshot.liveCitations.append(annotation)
            draft.annotations = execution.snapshot.liveCitations
        case let .filePathAnnotationAdded(annotation):
            execution.snapshot.liveFilePathAnnotations.append(annotation)
            draft.filePathAnnotations = execution.snapshot.liveFilePathAnnotations
        default:
            return
        }

        execution.snapshot.updatedAt = .now
        if resolvedBackgroundPersistence(for: conversation, coordinator: coordinator) {
            coordinator.persistSnapshot(execution, in: conversation, save: false)
        }
    }
}
