import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

@MainActor
extension AgentVisibleSynthesisEventApplier {
    static func applyLifecycleEvent(
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
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            refreshVisibleLeaderWritingPreview(execution: execution)
            execution.markProgress()
        case let .replaceText(text):
            execution.snapshot.currentStreamingText = text
            draft.content = text
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            refreshVisibleLeaderWritingPreview(execution: execution)
            execution.markProgress()
        case .thinkingStarted:
            execution.snapshot.isThinking = true
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Reasoning",
                summary: "Reasoning over accepted findings before final output.",
                execution: execution
            )
            execution.markProgress()
        case let .thinkingDelta(delta):
            execution.snapshot.isThinking = true
            execution.snapshot.currentThinkingText += delta
            draft.thinking = execution.snapshot.currentThinkingText
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            updateVisibleLeaderPreview(
                status: "Reasoning",
                summary: "Reasoning over accepted findings before final output.",
                execution: execution
            )
            execution.markProgress()
        case .thinkingFinished:
            execution.snapshot.isThinking = false
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            refreshVisibleLeaderWritingPreview(execution: execution)
            execution.markProgress()
        case let .responseCreated(responseID):
            let checkpointBaseResponseID = execution.snapshot.ticket(for: .leader)?.checkpointBaseResponseID
            coordinator.updateRoleResponseID(responseID, for: .leader, in: conversation)
            draft.responseId = responseID
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            persistVisibleLeaderTicket(
                responseID: responseID,
                checkpointBaseResponseID: checkpointBaseResponseID,
                sequenceNumber: nil,
                execution: execution,
                conversation: conversation,
                coordinator: coordinator,
                forceSave: true
            )
            coordinator.persistSnapshot(execution, in: conversation)
            execution.markProgress()
        case let .sequenceUpdate(sequenceNumber):
            draft.lastSequenceNumber = sequenceNumber
            AgentVisibleSynthesisProjector.updateRecoveryState(.idle, on: &execution.snapshot)
            persistVisibleLeaderTicket(
                responseID: draft.responseId,
                sequenceNumber: sequenceNumber,
                execution: execution,
                conversation: conversation,
                coordinator: coordinator,
                forceSave: true
            )
            execution.markProgress()
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
            execution.markProgress()
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
            throw AgentRunFailure.connectionLost("Agent synthesis lost its connection.")
        case let .error(error):
            throw AgentRunFailure.invalidResponse(error.localizedDescription)
        default:
            return false
        }

        execution.snapshot.updatedAt = .now
        return true
    }
}
