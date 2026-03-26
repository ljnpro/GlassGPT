import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
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
        switch stage {
        case .leaderBrief:
            execution.snapshot.phase = .leaderTriage
        case .workersRoundOne:
            execution.snapshot.phase = .workerWave
        case .crossReview:
            execution.snapshot.phase = .leaderReview
        case .finalSynthesis:
            execution.snapshot.phase = .finalSynthesis
        }
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

    func updateTicket(
        _ ticket: AgentRunTicket?,
        for role: AgentRole,
        execution: AgentExecutionState,
        conversation: Conversation,
        forceSave: Bool = false
    ) {
        execution.snapshot.setTicket(ticket, for: role)
        persistCheckpointIfNeeded(
            execution,
            in: conversation,
            forceSave: forceSave
        )
    }

    func clearTicket(
        for role: AgentRole,
        execution: AgentExecutionState,
        conversation: Conversation,
        forceSave: Bool = false
    ) {
        updateTicket(nil, for: role, execution: execution, conversation: conversation, forceSave: forceSave)
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
        execution.snapshot.lastCheckpointAt = .now
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

    func persistCheckpointIfNeeded(
        _ execution: AgentExecutionState,
        in conversation: Conversation,
        forceSave: Bool = false
    ) {
        let backgroundEnabled = execution.snapshot.runConfiguration.backgroundModeEnabled
        let age = Date().timeIntervalSince(execution.snapshot.lastCheckpointAt)
        let shouldSave = forceSave || (backgroundEnabled && age >= 0.5)
        persistSnapshot(execution, in: conversation, save: shouldSave)
    }

    func completedWorkerSummaries(from snapshot: AgentProcessSnapshot) -> [AgentWorkerSummary] {
        AgentSummaryFormatter.workerSummaries(from: snapshot)
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

    func frozenRunConfiguration(
        for execution: AgentExecutionState,
        conversation: Conversation
    ) -> AgentConversationConfiguration {
        if execution.snapshot.hasExplicitRunConfiguration {
            return execution.snapshot.runConfiguration
        }
        if let activeRun = conversation.agentConversationState?.activeRun,
           activeRun.hasExplicitRunConfiguration {
            return activeRun.runConfiguration
        }
        if let configuration = conversation.agentConversationState?.configuration {
            return configuration
        }
        if let snapshotConfiguration = conversation.agentConversationState?.activeRun?.runConfiguration {
            return snapshotConfiguration
        }
        return AgentConversationConfiguration(
            leaderReasoningEffort: ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high,
            workerReasoningEffort: .low,
            backgroundModeEnabled: conversation.backgroundModeEnabled,
            serviceTier: ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
        )
    }

    func isVisibleConversation(_ conversation: Conversation) -> Bool {
        state.currentConversation?.id == conversation.id && state.sessionRegistry.isVisible(conversation.id)
    }
}
