import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    func finalizeSuccessfulTurn(
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        outcome: String,
        stopReason _: AgentStopReason
    ) throws {
        guard let draft = prepared.conversation.messages.first(where: { $0.id == prepared.draftMessageID }) else {
            throw AgentRunFailure.missingDraft
        }

        draft.content = execution.snapshot.currentStreamingText
        draft.thinking = execution.snapshot.currentThinkingText.isEmpty
            ? nil
            : execution.snapshot.currentThinkingText
        draft.toolCalls = execution.snapshot.activeToolCalls
        draft.annotations = execution.snapshot.liveCitations
        draft.filePathAnnotations = execution.snapshot.liveFilePathAnnotations
        let synthesisContext = finalSynthesisContext(from: execution.snapshot.processSnapshot)
        let leaderSummary = execution.snapshot.leaderBriefSummary
            ?? {
                let acceptedFocus = execution.snapshot.processSnapshot.leaderAcceptedFocus
                return acceptedFocus.isEmpty ? execution.snapshot.processSnapshot.currentFocus : acceptedFocus
            }()
        draft.agentTrace = AgentTurnTrace(
            leaderBriefSummary: leaderSummary,
            workerSummaries: synthesisContext.workerSummaries,
            processSnapshot: execution.snapshot.processSnapshot,
            completedStage: .finalSynthesis,
            outcome: outcome
        )
        draft.isComplete = true

        prepared.conversation.updatedAt = .now
        var agentState = currentAgentState(for: prepared.conversation)
        agentState.currentStage = nil
        agentState.activeRun = nil
        agentState.updatedAt = .now
        prepared.conversation.agentConversationState = agentState

        guard state.conversationCoordinator.saveContext("finalizeSuccessfulTurn") else {
            throw AgentRunFailure.invalidResponse("Failed to save the final Agent answer.")
        }

        let wasVisible = isVisibleConversation(prepared.conversation)
        state.sessionRegistry.finishExecution(for: prepared.conversation.id)
        guard wasVisible else { return }

        state.messages = state.conversationCoordinator.visibleMessages(for: prepared.conversation)
        state.conversationCoordinator.clearVisibleRunState(clearDraft: true)
        state.errorMessage = nil
        state.hapticService.notify(.success, isEnabled: state.hapticsEnabled)
    }

    func finishWithFailure(
        _ failure: AgentRunFailure,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState
    ) {
        guard let draft = prepared.conversation.messages.first(where: { $0.id == prepared.draftMessageID }) else {
            state.sessionRegistry.finishExecution(for: prepared.conversation.id)
            return
        }

        draft.content = execution.snapshot.currentStreamingText
        draft.thinking = execution.snapshot.currentThinkingText.isEmpty
            ? nil
            : execution.snapshot.currentThinkingText
        draft.toolCalls = execution.snapshot.activeToolCalls
        draft.annotations = execution.snapshot.liveCitations
        draft.filePathAnnotations = execution.snapshot.liveFilePathAnnotations
        draft.isComplete = false

        let stopReason: AgentStopReason = switch failure {
        case .cancelled:
            .cancelled
        default:
            .incomplete
        }
        let shouldPreserveCompletedCouncil =
            execution.snapshot.currentStage == .finalSynthesis &&
            (execution.snapshot.processSnapshot.activity == .completed
                || execution.snapshot.processSnapshot.activity == .waitingForUser)
        if shouldPreserveCompletedCouncil {
            execution.snapshot.phase = .failed
            execution.snapshot.updatedAt = .now
            execution.snapshot.lastCheckpointAt = .now
            execution.snapshot.visibleSynthesisPresentation = AgentVisibleSynthesisPresentation(
                statusText: "Failed",
                summaryText: failure.userMessage,
                recoveryState: .idle
            )
        } else {
            AgentProcessProjector.finalize(
                outcome: failure.userMessage,
                stopReason: stopReason,
                activity: .failed,
                on: &execution.snapshot
            )
        }
        execution.snapshot.updatedAt = .now
        var agentState = currentAgentState(for: prepared.conversation)
        agentState.currentStage = nil
        agentState.activeRun = execution.snapshot
        agentState.updatedAt = .now
        prepared.conversation.agentConversationState = agentState
        prepared.conversation.updatedAt = .now
        _ = state.conversationCoordinator.saveContext("finishWithFailure")

        let wasVisible = isVisibleConversation(prepared.conversation)
        state.sessionRegistry.finishExecution(for: prepared.conversation.id)
        guard wasVisible else { return }

        state.messages = state.conversationCoordinator.visibleMessages(for: prepared.conversation)
        state.conversationCoordinator.applyPersistedSnapshot(execution.snapshot, draft: draft)
        state.isRunning = false
        state.isStreaming = false
        state.isThinking = false
        state.errorMessage = failure.userMessage
        state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
    }
}
