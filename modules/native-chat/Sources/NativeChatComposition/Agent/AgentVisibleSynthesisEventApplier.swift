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
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Searching the web",
                summary: "Checking supporting evidence before the final answer.",
                execution: execution
            )
        case let .webSearchSearching(id):
            setToolCallStatus(id: id, status: .searching, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Searching the web",
                summary: "Checking supporting evidence before the final answer.",
                execution: execution
            )
        case let .webSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            refreshVisibleLeaderWritingPreview(execution: execution)
        case let .codeInterpreterStarted(id):
            startToolCall(id: id, type: .codeInterpreter, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Running code",
                summary: "Validating the final answer with code execution.",
                execution: execution
            )
        case let .codeInterpreterInterpreting(id):
            setToolCallStatus(id: id, status: .interpreting, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Running code",
                summary: "Validating the final answer with code execution.",
                execution: execution
            )
        case let .codeInterpreterCodeDelta(id, delta):
            appendToolCode(id: id, delta: delta, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        case let .codeInterpreterCodeDone(id, code):
            setToolCode(id: id, code: code, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        case let .codeInterpreterCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            refreshVisibleLeaderWritingPreview(execution: execution)
        case let .fileSearchStarted(id):
            startToolCall(id: id, type: .fileSearch, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Searching files",
                summary: "Checking supporting files before the final answer.",
                execution: execution
            )
        case let .fileSearchSearching(id):
            setToolCallStatus(id: id, status: .fileSearching, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Searching files",
                summary: "Checking supporting files before the final answer.",
                execution: execution
            )
        case let .fileSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, execution: execution, draft: draft)
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            refreshVisibleLeaderWritingPreview(execution: execution)
        default:
            return false
        }

        execution.snapshot.updatedAt = .now
        execution.markProgress()
        coordinator.persistCheckpointIfNeeded(execution, in: conversation)
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
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        case let .filePathAnnotationAdded(annotation):
            execution.snapshot.liveFilePathAnnotations.append(annotation)
            draft.filePathAnnotations = execution.snapshot.liveFilePathAnnotations
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
        default:
            return
        }

        execution.snapshot.updatedAt = .now
        execution.markProgress()
        coordinator.persistCheckpointIfNeeded(execution, in: conversation)
    }
}
