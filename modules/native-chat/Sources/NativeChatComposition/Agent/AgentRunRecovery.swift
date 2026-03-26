import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    enum ResumeReplacementDisposition {
        case keep
        case replaceAndPersistExecutionSnapshot
        case replaceUsingPersistedRecoverableState
    }

    func resumeReplacementDisposition(
        for execution: AgentExecutionState,
        in conversation: Conversation? = nil
    ) -> ResumeReplacementDisposition {
        guard execution.snapshot.phase.supportsAutomaticResume else {
            return .keep
        }

        if let conversation, !activeExecutionMatchesRecoverableState(execution, in: conversation) {
            return .replaceUsingPersistedRecoverableState
        }

        if execution.needsForegroundResume {
            return .replaceAndPersistExecutionSnapshot
        }

        if execution.task == nil || execution.task?.isCancelled == true {
            return .replaceAndPersistExecutionSnapshot
        }

        if let lastBackgroundedAt = execution.lastBackgroundedAt,
           execution.lastProgressAt <= lastBackgroundedAt {
            return .replaceAndPersistExecutionSnapshot
        }

        return .keep
    }

    func shouldReplaceExecutionForResume(
        _ execution: AgentExecutionState,
        in conversation: Conversation? = nil
    ) -> Bool {
        resumeReplacementDisposition(for: execution, in: conversation) != .keep
    }

    func activeExecutionMatchesRecoverableState(
        _ execution: AgentExecutionState,
        in conversation: Conversation
    ) -> Bool {
        guard execution.conversationID == conversation.id else {
            return false
        }
        guard let draft = conversation.messages.first(where: {
            $0.id == execution.draftMessageID && $0.role == .assistant && !$0.isComplete
        }) else {
            return false
        }

        if let persistedRun = conversation.agentConversationState?.activeRun {
            guard persistedRun.draftMessageID == execution.draftMessageID,
                  persistedRun.latestUserMessageID == execution.latestUserMessageID
            else {
                return false
            }

            if !ticketsMatch(persistedRun.leaderTicket, execution.snapshot.leaderTicket) ||
                !ticketsMatch(persistedRun.workerATicket, execution.snapshot.workerATicket) ||
                !ticketsMatch(persistedRun.workerBTicket, execution.snapshot.workerBTicket) ||
                !ticketsMatch(persistedRun.workerCTicket, execution.snapshot.workerCTicket) {
                return false
            }
        }

        let persistedDraftResponseID = normalizedResponseID(draft.responseId)
        let executionDraftResponseID = normalizedResponseID(
            execution.snapshot.currentStage == .finalSynthesis
                ? (execution.snapshot.ticket(for: .leader)?.responseID ?? draft.responseId)
                : draft.responseId
        )
        if let persistedDraftResponseID,
           persistedDraftResponseID != executionDraftResponseID {
            return false
        }

        return true
    }

    private func ticketsMatch(_ expected: AgentRunTicket?, _ actual: AgentRunTicket?) -> Bool {
        switch (expected, actual) {
        case (nil, nil):
            return true
        case let (expected?, actual?):
            if expected.phase != actual.phase || expected.role != actual.role {
                return false
            }
            if expected.taskID != actual.taskID {
                return false
            }
            let expectedResponseID = normalizedResponseID(expected.responseID)
            let actualResponseID = normalizedResponseID(actual.responseID)
            return expectedResponseID == actualResponseID
        default:
            return false
        }
    }

    private func normalizedResponseID(_ responseID: String?) -> String? {
        guard let responseID else { return nil }
        let trimmed = responseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func resumePersistedRunIfNeeded(_ conversation: Conversation) async {
        if let execution = state.sessionRegistry.execution(for: conversation.id) {
            switch resumeReplacementDisposition(for: execution, in: conversation) {
            case .keep:
                syncVisibleStateIfNeeded(execution, in: conversation)
                return
            case .replaceAndPersistExecutionSnapshot:
                persistSnapshot(execution, in: conversation)
                let shouldStayVisible = state.sessionRegistry.isVisible(conversation.id)
                    || state.currentConversation?.id == conversation.id
                state.sessionRegistry.removeExecution(for: conversation.id)
                if shouldStayVisible {
                    state.sessionRegistry.bindVisibleConversation(conversation.id)
                }
            case .replaceUsingPersistedRecoverableState:
                let shouldStayVisible = state.sessionRegistry.isVisible(conversation.id)
                    || state.currentConversation?.id == conversation.id
                state.sessionRegistry.removeExecution(for: conversation.id)
                if shouldStayVisible {
                    state.sessionRegistry.bindVisibleConversation(conversation.id)
                }
            }
        }

        let apiKey = (state.apiKeyStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            if state.currentConversation?.id == conversation.id {
                state.errorMessage = "Please add your OpenAI API key in Settings."
            }
            return
        }

        guard let draft = resumableDraft(in: conversation) else {
            if state.currentConversation?.id == conversation.id {
                state.errorMessage = AgentConversationCoordinator.retryBannerMessage
            }
            return
        }

        let snapshot = resumableSnapshot(in: conversation, draft: draft)
        guard snapshot.phase.supportsAutomaticResume else {
            if state.currentConversation?.id == conversation.id {
                state.errorMessage = AgentConversationCoordinator.retryBannerMessage
            }
            return
        }
        var preparedSnapshot = snapshot
        AgentProcessProjector.prepareForResume(&preparedSnapshot)
        let latestUserText = latestUserText(
            in: conversation,
            preferredUserMessageID: preparedSnapshot.latestUserMessageID
        )
        guard conversation.messages.contains(where: { $0.id == preparedSnapshot.latestUserMessageID }) else {
            if state.currentConversation?.id == conversation.id {
                state.errorMessage = AgentConversationCoordinator.retryBannerMessage
            }
            return
        }

        let prepared = PreparedAgentTurn(
            apiKey: apiKey,
            conversation: conversation,
            draft: draft,
            configuration: resolvedConfiguration(for: conversation),
            latestUserText: latestUserText,
            userMessageID: preparedSnapshot.latestUserMessageID,
            draftMessageID: draft.id,
            attachmentsToUpload: conversation.messages
                .first(where: { $0.id == preparedSnapshot.latestUserMessageID })?
                .fileAttachments
                .filter { $0.fileId == nil || $0.uploadStatus != .uploaded } ?? []
        )
        startExecution(
            prepared,
            snapshot: preparedSnapshot,
            service: state.serviceFactory()
        )
    }

    func resumableDraft(in conversation: Conversation) -> Message? {
        let messages = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
        if let snapshot = conversation.agentConversationState?.activeRun,
           let snapshotDraft = messages.first(where: { $0.id == snapshot.draftMessageID }) {
            return snapshotDraft
        }

        return messages.last(where: { $0.role == .assistant && !$0.isComplete })
    }
}
