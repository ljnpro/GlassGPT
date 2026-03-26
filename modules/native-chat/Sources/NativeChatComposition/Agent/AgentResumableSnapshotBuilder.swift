import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    func resumableSnapshot(
        in conversation: Conversation,
        draft: Message
    ) -> AgentRunSnapshot {
        let latestUserMessageID = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == .user })?
            .id ?? UUID()
        let configuration = resolvedConfiguration(for: conversation)

        if let snapshot = conversation.agentConversationState?.activeRun {
            return normalizedResumableSnapshot(
                snapshot,
                in: conversation,
                draft: draft,
                latestUserMessageID: latestUserMessageID,
                configuration: configuration
            )
        }

        let inferredPhase = inferredResumablePhase(
            from: nil,
            in: conversation,
            draft: draft
        ) ?? .finalSynthesis

        let bootstrapFocus = fallbackFocus(
            for: inferredPhase,
            processSnapshot: AgentProcessSnapshot()
        )
        var snapshot = AgentRunSnapshot(
            currentStage: inferredPhase.compatibilityStage,
            phase: inferredPhase,
            draftMessageID: draft.id,
            latestUserMessageID: latestUserMessageID,
            runConfiguration: configuration,
            processSnapshot: AgentProcessSnapshot(
                activity: inferredPhase.compatibilityActivity,
                currentFocus: bootstrapFocus,
                leaderAcceptedFocus: inferredPhase == .finalSynthesis
                    ? "Leader completed the internal Agent council."
                    : bootstrapFocus,
                leaderLiveStatus: fallbackStatus(for: inferredPhase, processSnapshot: AgentProcessSnapshot()),
                leaderLiveSummary: fallbackSummary(for: inferredPhase, processSnapshot: AgentProcessSnapshot()),
                recentUpdateItems: [
                    AgentProcessUpdate(
                        kind: .runStarted,
                        source: .system,
                        phase: inferredPhase,
                        summary: "Started Agent run"
                    )
                ]
            ),
            currentStreamingText: inferredPhase == .finalSynthesis ? draft.content : "",
            currentThinkingText: inferredPhase == .finalSynthesis ? (draft.thinking ?? "") : "",
            visibleSynthesisPresentation: inferredPhase == .finalSynthesis
                ? AgentVisibleSynthesisPresentation(
                    statusText: "Writing final answer",
                    summaryText: "Writing final answer from accepted findings.",
                    recoveryState: .idle
                )
                : nil,
            activeToolCalls: inferredPhase == .finalSynthesis ? draft.toolCalls : [],
            liveCitations: inferredPhase == .finalSynthesis ? draft.annotations : [],
            liveFilePathAnnotations: inferredPhase == .finalSynthesis ? draft.filePathAnnotations : [],
            isStreaming: inferredPhase == .finalSynthesis,
            isThinking: false
        )
        normalizeResumableSnapshot(
            &snapshot,
            in: conversation,
            draft: draft,
            latestUserMessageID: latestUserMessageID,
            configuration: configuration
        )
        return snapshot
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
        if let activeRun = conversation.agentConversationState?.activeRun,
           activeRun.hasExplicitRunConfiguration {
            return activeRun.runConfiguration
        }

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
