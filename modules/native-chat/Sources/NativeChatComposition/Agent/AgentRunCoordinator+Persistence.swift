import ChatDomain
import OpenAITransport

extension AgentRunCoordinator {
    func finalizeSuccessfulTurn(
        leaderBrief: String,
        revisedWorkers: [HiddenWorkerRevision]
    ) throws {
        guard let draft = state.draftMessage else {
            throw AgentRunFailure.missingDraft
        }
        guard let conversation = state.currentConversation else {
            throw AgentRunFailure.missingConversation
        }

        draft.content = state.currentStreamingText
        draft.thinking = state.currentThinkingText.isEmpty ? nil : state.currentThinkingText
        draft.toolCalls = state.activeToolCalls
        draft.annotations = state.liveCitations
        draft.filePathAnnotations = state.liveFilePathAnnotations
        draft.agentTrace = AgentTurnTrace(
            leaderBriefSummary: leaderBrief,
            workerSummaries: makeWorkerSummaries(from: revisedWorkers),
            completedStage: .finalSynthesis,
            outcome: "Completed"
        )
        draft.isComplete = true

        conversation.updatedAt = .now
        var agentState = currentAgentState
        agentState.currentStage = nil
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState

        guard state.conversationCoordinator.saveContext("finalizeSuccessfulTurn") else {
            throw AgentRunFailure.invalidResponse("Failed to save the final Agent answer.")
        }

        state.messages = state.conversationCoordinator.visibleMessages(for: conversation)
        state.draftMessage = nil
        state.currentStage = nil
        state.isRunning = false
        state.isStreaming = false
        state.isThinking = false
        state.errorMessage = nil
        state.workerProgress = AgentWorkerProgress.defaultProgress
        state.hapticService.notify(.success, isEnabled: state.hapticsEnabled)
    }

    func finishWithFailure(_ failure: AgentRunFailure) {
        guard let conversation = state.currentConversation else { return }

        if let draft = state.draftMessage {
            draft.content = state.currentStreamingText
            draft.thinking = state.currentThinkingText.isEmpty ? nil : state.currentThinkingText
            draft.toolCalls = state.activeToolCalls
            draft.annotations = state.liveCitations
            draft.filePathAnnotations = state.liveFilePathAnnotations
            draft.isComplete = false
        }

        var agentState = currentAgentState
        agentState.currentStage = nil
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState
        conversation.updatedAt = .now
        _ = state.conversationCoordinator.saveContext("finishWithFailure")

        state.messages = state.conversationCoordinator.visibleMessages(for: conversation)
        state.isRunning = false
        state.isStreaming = false
        state.isThinking = false
        state.currentStage = nil
        state.errorMessage = failure.userMessage
        state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
    }

    func requireResponseID(from response: ResponsesResponseDTO) throws -> String {
        guard let responseID = response.id, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Responses API did not return a response id.")
        }
        return responseID
    }

    func updateStage(_ stage: AgentStage) {
        state.currentStage = stage
        guard let conversation = state.currentConversation else { return }

        var agentState = currentAgentState
        agentState.currentStage = stage
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState
        _ = state.conversationCoordinator.saveContext("updateStage")
    }

    func setAllWorkerStatuses(_ status: AgentWorkerProgress.Status) {
        for role in [AgentRole.workerA, .workerB, .workerC] {
            setWorkerStatus(status, for: role)
        }
    }

    func setWorkerStatus(_ status: AgentWorkerProgress.Status, for role: AgentRole) {
        guard let index = state.workerProgress.firstIndex(where: { $0.role == role }) else { return }
        state.workerProgress[index].status = status
    }

    func updateRoleResponseID(_ responseID: String?, for role: AgentRole) {
        guard let conversation = state.currentConversation else { return }

        var agentState = currentAgentState
        agentState.setResponseID(responseID, for: role)
        conversation.agentConversationState = agentState
        _ = state.conversationCoordinator.saveContext("updateRoleResponseID")
    }

    var currentAgentState: AgentConversationState {
        state.currentConversation?.agentConversationState ?? AgentConversationState()
    }
}
