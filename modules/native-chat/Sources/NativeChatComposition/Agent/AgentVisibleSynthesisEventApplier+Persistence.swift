import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

@MainActor
extension AgentVisibleSynthesisEventApplier {
    static func applyCompletionSnapshot(
        text: String,
        thinking: String?,
        fileAnnotations: [FilePathAnnotation]?,
        execution: AgentExecutionState,
        draft: Message
    ) {
        execution.snapshot.currentStreamingText = text
        execution.snapshot.isStreaming = false
        execution.snapshot.isThinking = false
        execution.snapshot.visibleSynthesisPresentation = AgentVisibleSynthesisPresentation(
            statusText: "Completed",
            summaryText: "Finished writing the final answer from accepted findings.",
            recoveryState: .idle
        )
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

    static func finishVisibleLifecycle(
        text: String,
        thinking: String?,
        fileAnnotations: [FilePathAnnotation]?,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message,
        coordinator: AgentRunCoordinator,
        incompleteMessage: String?
    ) throws {
        applyCompletionSnapshot(
            text: text,
            thinking: thinking,
            fileAnnotations: fileAnnotations,
            execution: execution,
            draft: draft
        )
        coordinator.clearTicket(
            for: .leader,
            execution: execution,
            conversation: conversation,
            forceSave: true
        )
        coordinator.persistSnapshot(execution, in: conversation)
        if let incompleteMessage {
            throw AgentRunFailure.incomplete(incompleteMessage)
        }
    }

    static func persistVisibleLeaderTicket(
        responseID: String?,
        checkpointBaseResponseID: String? = nil,
        sequenceNumber: Int?,
        execution: AgentExecutionState,
        conversation: Conversation,
        coordinator: AgentRunCoordinator,
        forceSave: Bool
    ) {
        var ticket = execution.snapshot.ticket(for: .leader) ?? AgentRunTicket(
            role: .leader,
            phase: .finalSynthesis,
            backgroundEligible: execution.snapshot.runConfiguration.backgroundModeEnabled
        )
        ticket.responseID = responseID
        ticket.checkpointBaseResponseID = checkpointBaseResponseID ?? ticket.checkpointBaseResponseID
        ticket.lastSequenceNumber = sequenceNumber
        ticket.partialOutputText = execution.snapshot.currentStreamingText
        ticket.statusText = execution.snapshot.visibleSynthesisPresentation?.statusText ?? ""
        ticket.summaryText = execution.snapshot.visibleSynthesisPresentation?.summaryText ?? ""
        ticket.toolCalls = execution.snapshot.activeToolCalls
        coordinator.updateTicket(
            ticket,
            for: .leader,
            execution: execution,
            conversation: conversation,
            forceSave: forceSave
        )
    }
}
