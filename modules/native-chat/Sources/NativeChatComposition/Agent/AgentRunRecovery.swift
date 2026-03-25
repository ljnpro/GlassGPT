import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func resumePersistedRunIfNeeded(_ conversation: Conversation) async {
        guard state.sessionRegistry.execution(for: conversation.id) == nil else {
            if let execution = state.sessionRegistry.execution(for: conversation.id) {
                syncVisibleStateIfNeeded(execution, in: conversation)
            }
            return
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
            attachmentsToUpload: []
        )
        startExecution(
            prepared,
            snapshot: preparedSnapshot,
            service: state.serviceFactory()
        )
    }

    func recoverVisibleLeaderSynthesis(
        apiKey: String,
        conversation: Conversation,
        draft: Message,
        execution: AgentExecutionState
    ) async throws {
        updateStage(.finalSynthesis, execution: execution, in: conversation)
        setStreamingFlags(
            isStreaming: true,
            isThinking: execution.snapshot.isThinking,
            execution: execution,
            conversation: conversation,
            persist: false
        )

        guard let responseID = draft.responseId, !responseID.isEmpty else {
            throw AgentRunFailure.missingDraft
        }

        let result = try await execution.service.fetchResponse(responseId: responseID, apiKey: apiKey)
        switch result.status {
        case .completed:
            applyFetchedResponse(result, to: execution, conversation: conversation)
        case .failed:
            throw AgentRunFailure.invalidResponse(
                result.errorMessage ?? "Agent synthesis failed."
            )
        case .incomplete:
            applyFetchedResponse(result, to: execution, conversation: conversation)
            throw AgentRunFailure.incomplete(
                result.errorMessage ?? "Agent synthesis was incomplete."
            )
        case .queued, .inProgress, .unknown:
            if let lastSequenceNumber = draft.lastSequenceNumber {
                let recoveryStream = execution.service.streamRecovery(
                    responseId: responseID,
                    startingAfter: lastSequenceNumber,
                    apiKey: apiKey
                )

                for await event in recoveryStream {
                    try Task.checkCancellation()
                    try applyVisibleStreamEvent(
                        event,
                        execution: execution,
                        conversation: conversation,
                        draft: draft
                    )
                }
            } else {
                try await pollVisibleLeaderSynthesis(
                    apiKey: apiKey,
                    responseID: responseID,
                    execution: execution,
                    conversation: conversation
                )
            }
        }
    }

    func pollVisibleLeaderSynthesis(
        apiKey: String,
        responseID: String,
        execution: AgentExecutionState,
        conversation: Conversation
    ) async throws {
        let maxAttempts = 30

        for attempt in 0 ..< maxAttempts {
            try Task.checkCancellation()
            let result = try await execution.service.fetchResponse(responseId: responseID, apiKey: apiKey)

            switch result.status {
            case .completed:
                applyFetchedResponse(result, to: execution, conversation: conversation)
                return
            case .failed:
                throw AgentRunFailure.invalidResponse(
                    result.errorMessage ?? "Agent synthesis failed."
                )
            case .incomplete:
                applyFetchedResponse(result, to: execution, conversation: conversation)
                throw AgentRunFailure.incomplete(
                    result.errorMessage ?? "Agent synthesis was incomplete."
                )
            case .queued, .inProgress, .unknown:
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }

        throw AgentRunFailure.incomplete("Agent synthesis is still in progress. Retry to continue.")
    }

    func applyFetchedResponse(
        _ result: OpenAIResponseFetchResult,
        to execution: AgentExecutionState,
        conversation: Conversation
    ) {
        if let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) {
            draft.content = result.text
            draft.thinking = result.thinking
            draft.toolCalls = result.toolCalls
            draft.annotations = result.annotations
            draft.filePathAnnotations = result.filePathAnnotations
        }

        execution.snapshot.currentStreamingText = result.text
        execution.snapshot.currentThinkingText = result.thinking ?? ""
        execution.snapshot.liveCitations = result.annotations
        execution.snapshot.activeToolCalls = result.toolCalls
        execution.snapshot.liveFilePathAnnotations = result.filePathAnnotations
        execution.snapshot.isStreaming = false
        execution.snapshot.isThinking = false
        execution.snapshot.updatedAt = .now
        syncVisibleStateIfNeeded(execution, in: conversation)
    }

    func resumableDraft(in conversation: Conversation) -> Message? {
        let messages = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
        if let snapshot = conversation.agentConversationState?.activeRun,
           let snapshotDraft = messages.first(where: { $0.id == snapshot.draftMessageID }) {
            return snapshotDraft
        }

        return messages.last(where: { $0.role == .assistant && !$0.isComplete })
    }

    func resumableSnapshot(
        in conversation: Conversation,
        draft: Message
    ) -> AgentRunSnapshot {
        if let snapshot = conversation.agentConversationState?.activeRun {
            return snapshot
        }

        let latestUserMessageID = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .user })?
            .id ?? UUID()

        return AgentRunSnapshot(
            currentStage: .finalSynthesis,
            draftMessageID: draft.id,
            latestUserMessageID: latestUserMessageID,
            processSnapshot: AgentProcessSnapshot(
                activity: .synthesis,
                currentFocus: "Leader is finishing the answer."
            ),
            currentStreamingText: draft.content,
            currentThinkingText: draft.thinking ?? "",
            activeToolCalls: draft.toolCalls,
            liveCitations: draft.annotations,
            liveFilePathAnnotations: draft.filePathAnnotations,
            isStreaming: true,
            isThinking: false
        )
    }

    func latestUserText(
        in conversation: Conversation,
        preferredUserMessageID: UUID
    ) -> String {
        let messages = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })

        if let preferred = messages.first(where: { $0.id == preferredUserMessageID })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !preferred.isEmpty {
            return preferred
        }

        return messages
            .last(where: { $0.role == .user })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func resolvedConfiguration(for conversation: Conversation) -> AgentConversationConfiguration {
        if let configuration = conversation.agentConversationState?.configuration {
            return configuration
        }

        return AgentConversationConfiguration(
            leaderReasoningEffort: ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high,
            workerReasoningEffort: .low,
            backgroundModeEnabled: conversation.backgroundModeEnabled,
            serviceTier: ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
        )
    }
}
