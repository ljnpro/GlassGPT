import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentConversationCoordinator {
    static let retryBannerMessage = "The last Agent run did not complete. Retry to continue."

    func beginVisibleRun(with draft: Message, latestUserMessageID: UUID) {
        if let conversation = state.currentConversation {
            state.sessionRegistry.bindVisibleConversation(conversation.id)
            var agentState = conversation.agentConversationState ?? AgentConversationState()
            let snapshot = AgentProcessProjector.makeInitialRunSnapshot(
                draftMessageID: draft.id,
                latestUserMessageID: latestUserMessageID,
                configuration: agentState.configuration
            )
            agentState.activeRun = snapshot
            agentState.currentStage = .leaderBrief
            agentState.updatedAt = .now
            conversation.agentConversationState = agentState
            applyPersistedSnapshot(snapshot, draft: draft)
            state.errorMessage = nil
        }
        state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)
    }

    func restoreDraftIfNeeded(
        from conversation: Conversation,
        autoResume: Bool = true,
        showRetryBannerWhenDormant: Bool = true
    ) {
        clearVisibleRunState(clearDraft: true)

        if let execution = state.sessionRegistry.execution(for: conversation.id) {
            if let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) {
                state.sessionRegistry.bindVisibleConversation(conversation.id)
                applyPersistedSnapshot(execution.snapshot, draft: draft)
            }
            let disposition = state.runCoordinator.resumeReplacementDisposition(for: execution, in: conversation)
            if autoResume, disposition != .keep {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
                }
            } else {
                bindVisibleExecution(execution, in: conversation)
            }
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
        if conversation.agentConversationState?.activeRun != nil {
            let snapshot = state.runCoordinator.resumableSnapshot(in: conversation, draft: draft)
            applyPersistedSnapshot(snapshot, draft: draft)
            if autoResume,
               snapshot.phase.supportsAutomaticResume {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
                }
            } else if showRetryBannerWhenDormant,
                      shouldShowRetryBanner(for: snapshot) {
                state.errorMessage = Self.retryBannerMessage
            }
            return
        }

        let snapshot = state.runCoordinator.resumableSnapshot(in: conversation, draft: draft)
        applyPersistedSnapshot(snapshot, draft: draft)
        if autoResume, snapshot.phase.supportsAutomaticResume {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
            }
        } else if showRetryBannerWhenDormant {
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
        state.processSnapshot = snapshot.processSnapshot
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
        state.processSnapshot = AgentProcessSnapshot()
        state.workersRoundOneProgress = AgentWorkerProgress.defaultProgress
        state.crossReviewProgress = AgentWorkerProgress.defaultProgress
    }

    private func shouldShowRetryBanner(for snapshot: AgentRunSnapshot) -> Bool {
        if snapshot.phase == .failed {
            return true
        }
        return !snapshot.phase.supportsAutomaticResume
    }
}
