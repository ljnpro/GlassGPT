import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func finalizeSuccessfulTurn(
        leaderBrief: String,
        revisedWorkers: [HiddenWorkerRevision],
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState
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
        draft.agentTrace = AgentTurnTrace(
            leaderBriefSummary: leaderBrief,
            workerSummaries: makeWorkerSummaries(from: revisedWorkers),
            completedStage: .finalSynthesis,
            outcome: "Completed"
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

    func requireResponseID(from response: ResponsesResponseDTO) throws -> String {
        guard let responseID = response.id, !responseID.isEmpty else {
            throw AgentRunFailure.invalidResponse("Responses API did not return a response id.")
        }
        return responseID
    }

    func updateStage(
        _ stage: AgentStage,
        execution: AgentExecutionState,
        in conversation: Conversation
    ) {
        execution.snapshot.currentStage = stage
        execution.snapshot.updatedAt = .now
        switch stage {
        case .workersRoundOne:
            execution.snapshot.workersRoundOneProgress = AgentWorkerProgress.defaultProgress
        case .crossReview:
            execution.snapshot.crossReviewProgress = AgentWorkerProgress.defaultProgress
        case .leaderBrief, .finalSynthesis:
            break
        }
        persistSnapshot(execution, in: conversation)
    }

    func setStreamingFlags(
        isStreaming: Bool,
        isThinking: Bool,
        execution: AgentExecutionState,
        conversation: Conversation,
        persist: Bool
    ) {
        execution.snapshot.isStreaming = isStreaming
        execution.snapshot.isThinking = isThinking
        execution.snapshot.updatedAt = .now
        if persist {
            persistSnapshot(execution, in: conversation)
        } else {
            syncVisibleStateIfNeeded(execution, in: conversation)
        }
    }

    func updateLeaderBriefSummary(
        _ summary: String,
        execution: AgentExecutionState,
        conversation: Conversation
    ) {
        execution.snapshot.leaderBriefSummary = summary
        execution.snapshot.updatedAt = .now
        persistSnapshot(execution, in: conversation)
    }

    func storeWorkerRoundOneSummaries(
        _ rounds: [HiddenWorkerRound],
        execution: AgentExecutionState,
        conversation: Conversation
    ) {
        execution.snapshot.workersRoundOneSummaries = rounds.map {
            AgentWorkerSummary(role: $0.role, summary: $0.summary)
        }
        execution.snapshot.updatedAt = .now
        persistSnapshot(execution, in: conversation)
    }

    func storeCrossReviewSummaries(
        _ revisions: [HiddenWorkerRevision],
        execution: AgentExecutionState,
        conversation: Conversation
    ) {
        execution.snapshot.crossReviewSummaries = makeWorkerSummaries(from: revisions)
        execution.snapshot.updatedAt = .now
        persistSnapshot(execution, in: conversation)
    }

    func setAllWorkerStatuses(
        _ status: AgentWorkerProgress.Status,
        stage: AgentStage,
        execution: AgentExecutionState,
        conversation: Conversation
    ) {
        for role in [AgentRole.workerA, .workerB, .workerC] {
            setWorkerStatus(status, for: role, stage: stage, execution: execution, conversation: conversation)
        }
    }

    func setWorkerStatus(
        _ status: AgentWorkerProgress.Status,
        for role: AgentRole,
        stage: AgentStage,
        execution: AgentExecutionState,
        conversation: Conversation
    ) {
        switch stage {
        case .workersRoundOne:
            guard let index = execution.snapshot.workersRoundOneProgress.firstIndex(where: { $0.role == role }) else {
                return
            }
            execution.snapshot.workersRoundOneProgress[index].status = status
        case .crossReview:
            guard let index = execution.snapshot.crossReviewProgress.firstIndex(where: { $0.role == role }) else {
                return
            }
            execution.snapshot.crossReviewProgress[index].status = status
        case .leaderBrief, .finalSynthesis:
            return
        }
        execution.snapshot.updatedAt = .now
        persistSnapshot(execution, in: conversation)
    }

    func updateRoleResponseID(
        _ responseID: String?,
        for role: AgentRole,
        in conversation: Conversation
    ) {
        var agentState = currentAgentState(for: conversation)
        agentState.setResponseID(responseID, for: role)
        if role == .leader, let responseID {
            conversation.messages
                .first(where: { $0.id == agentState.activeRun?.draftMessageID })?
                .responseId = responseID
        }
        conversation.agentConversationState = agentState
        _ = state.conversationCoordinator.saveContext("updateRoleResponseID")
    }

    func persistSnapshot(
        _ execution: AgentExecutionState,
        in conversation: Conversation,
        save: Bool = true
    ) {
        execution.snapshot.updatedAt = .now
        var agentState = currentAgentState(for: conversation)
        agentState.currentStage = execution.snapshot.currentStage
        agentState.activeRun = execution.snapshot
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState
        conversation.updatedAt = .now
        if save {
            _ = state.conversationCoordinator.saveContext("persistSnapshot")
        }
        syncVisibleStateIfNeeded(execution, in: conversation)
    }

    func syncVisibleStateIfNeeded(_ execution: AgentExecutionState, in conversation: Conversation) {
        guard isVisibleConversation(conversation),
              let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID })
        else {
            return
        }

        state.messages = state.conversationCoordinator.visibleMessages(for: conversation)
        state.conversationCoordinator.bindVisibleExecution(execution, in: conversation)
        draft.content = execution.snapshot.currentStreamingText
        draft.thinking = execution.snapshot.currentThinkingText.isEmpty
            ? nil
            : execution.snapshot.currentThinkingText
        draft.toolCalls = execution.snapshot.activeToolCalls
        draft.annotations = execution.snapshot.liveCitations
        draft.filePathAnnotations = execution.snapshot.liveFilePathAnnotations
    }

    func currentAgentState(for conversation: Conversation) -> AgentConversationState {
        conversation.agentConversationState ?? AgentConversationState()
    }

    func isVisibleConversation(_ conversation: Conversation) -> Bool {
        state.currentConversation?.id == conversation.id && state.sessionRegistry.isVisible(conversation.id)
    }
}
