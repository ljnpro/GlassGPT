import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentConversationCoordinator {
    static let retryBannerMessage = "The last Agent run did not complete. Retry to continue."

    func beginVisibleRun(with draft: Message, latestUserMessageID: UUID) {
        state.draftMessage = draft
        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.errorMessage = nil
        state.isRunning = true
        state.isStreaming = false
        state.isThinking = false
        state.currentStage = .leaderBrief
        state.leaderBriefSummary = nil
        state.workersRoundOneProgress = AgentWorkerProgress.defaultProgress
        state.crossReviewProgress = AgentWorkerProgress.defaultProgress
        if let conversation = state.currentConversation {
            state.sessionRegistry.bindVisibleConversation(conversation.id)
            var agentState = conversation.agentConversationState ?? AgentConversationState()
            agentState.activeRun = AgentRunSnapshot(
                currentStage: .leaderBrief,
                draftMessageID: draft.id,
                latestUserMessageID: latestUserMessageID
            )
            agentState.currentStage = .leaderBrief
            agentState.updatedAt = .now
            conversation.agentConversationState = agentState
        }
        state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)
    }

    func restoreDraftIfNeeded(from conversation: Conversation) {
        clearVisibleRunState(clearDraft: true)

        if let execution = state.sessionRegistry.execution(for: conversation.id) {
            bindVisibleExecution(execution, in: conversation)
            return
        }

        guard let draft = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .assistant && !$0.isComplete })
        else {
            state.sessionRegistry.bindVisibleConversation(nil)
            return
        }

        state.draftMessage = draft
        if let snapshot = conversation.agentConversationState?.activeRun {
            applyPersistedSnapshot(snapshot, draft: draft)
            if resolvedConfiguration(for: conversation).backgroundModeEnabled {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
                }
            } else {
                state.errorMessage = Self.retryBannerMessage
            }
            return
        }

        state.currentStreamingText = draft.content
        state.currentThinkingText = draft.thinking ?? ""
        state.activeToolCalls = draft.toolCalls
        state.liveCitations = draft.annotations
        state.liveFilePathAnnotations = draft.filePathAnnotations
        if resolvedConfiguration(for: conversation).backgroundModeEnabled, draft.responseId != nil {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
            }
        } else {
            state.errorMessage = Self.retryBannerMessage
        }
    }

    func bindVisibleExecution(_ execution: AgentExecutionState, in conversation: Conversation) {
        state.sessionRegistry.bindVisibleConversation(conversation.id)
        guard let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) else {
            clearVisibleRunState(clearDraft: true)
            return
        }

        state.draftMessage = draft
        applyPersistedSnapshot(execution.snapshot, draft: draft)
        state.errorMessage = nil
    }

    func applyPersistedSnapshot(_ snapshot: AgentRunSnapshot, draft: Message) {
        state.draftMessage = draft
        state.currentStreamingText = snapshot.currentStreamingText
        state.currentThinkingText = snapshot.currentThinkingText
        state.activeToolCalls = snapshot.activeToolCalls
        state.liveCitations = snapshot.liveCitations
        state.liveFilePathAnnotations = snapshot.liveFilePathAnnotations
        state.isRunning = true
        state.isStreaming = snapshot.isStreaming
        state.isThinking = snapshot.isThinking
        state.currentStage = snapshot.currentStage
        state.leaderBriefSummary = snapshot.leaderBriefSummary
        state.workersRoundOneProgress = snapshot.workersRoundOneProgress
        state.crossReviewProgress = snapshot.crossReviewProgress
    }

    func clearVisibleRunState(clearDraft: Bool) {
        state.draftMessage = clearDraft ? nil : state.draftMessage
        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.isRunning = false
        state.isStreaming = false
        state.isThinking = false
        state.currentStage = nil
        state.leaderBriefSummary = nil
        state.workersRoundOneProgress = AgentWorkerProgress.defaultProgress
        state.crossReviewProgress = AgentWorkerProgress.defaultProgress
    }
}
