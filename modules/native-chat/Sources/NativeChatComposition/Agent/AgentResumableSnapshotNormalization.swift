import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentRunCoordinator {
    func normalizedResumableSnapshot(
        _ snapshot: AgentRunSnapshot,
        in conversation: Conversation,
        draft: Message,
        latestUserMessageID: UUID,
        configuration: AgentConversationConfiguration
    ) -> AgentRunSnapshot {
        var normalized = snapshot
        normalizeResumableSnapshot(
            &normalized,
            in: conversation,
            draft: draft,
            latestUserMessageID: latestUserMessageID,
            configuration: configuration
        )
        return normalized
    }

    func normalizeResumableSnapshot(
        _ snapshot: inout AgentRunSnapshot,
        in conversation: Conversation,
        draft: Message,
        latestUserMessageID: UUID,
        configuration: AgentConversationConfiguration
    ) {
        if !snapshot.hasExplicitRunConfiguration {
            snapshot.runConfiguration = configuration
            snapshot.hasExplicitRunConfiguration = true
        }
        if !conversation.messages.contains(where: { $0.id == snapshot.latestUserMessageID }) {
            snapshot.latestUserMessageID = latestUserMessageID
        }

        let phase = inferredResumablePhase(from: snapshot, in: conversation, draft: draft) ?? snapshot.phase
        snapshot.phase = phase
        snapshot.currentStage = phase.compatibilityStage
        backfillCheckpointBaseResponseIDs(on: &snapshot, in: conversation)
        snapshot.processSnapshot = normalizedProcessSnapshot(
            for: phase,
            snapshot: snapshot,
            conversation: conversation
        )

        if phase == .finalSynthesis {
            snapshot.currentStreamingText = draft.content
            snapshot.currentThinkingText = draft.thinking ?? ""
            snapshot.activeToolCalls = draft.toolCalls
            snapshot.liveCitations = draft.annotations
            snapshot.liveFilePathAnnotations = draft.filePathAnnotations
            snapshot.isStreaming = true
            snapshot.isThinking = false
            snapshot.visibleSynthesisPresentation = snapshot.visibleSynthesisPresentation
                ?? AgentVisibleSynthesisPresentation(
                    statusText: "Writing final answer",
                    summaryText: "Writing final answer from accepted findings.",
                    recoveryState: .idle
                )
        } else {
            snapshot.currentStreamingText = ""
            snapshot.currentThinkingText = ""
            snapshot.activeToolCalls = []
            snapshot.liveCitations = []
            snapshot.liveFilePathAnnotations = []
            snapshot.isStreaming = false
            snapshot.isThinking = false
            snapshot.visibleSynthesisPresentation = nil
        }

        AgentRecentUpdateProjector.sanitizeRecentUpdates(on: &snapshot)
    }

    func normalizedProcessSnapshot(
        for phase: AgentRunPhase,
        snapshot: AgentRunSnapshot,
        conversation: Conversation
    ) -> AgentProcessSnapshot {
        var process = snapshot.processSnapshot
        let wasFailed = process.activity == .failed
        process.updatedAt = .now
        process.recoveryState = .idle

        if phase == .finalSynthesis {
            let acceptedFocus = process.leaderAcceptedFocus.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentFocus = process.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedFocus = acceptedFocus.isEmpty
                ? (currentFocus.isEmpty ? "Leader completed the internal Agent council." : currentFocus)
                : acceptedFocus
            process.activity = .completed
            process.currentFocus = resolvedFocus
            process.leaderAcceptedFocus = resolvedFocus
            process.leaderLiveStatus = "Done"
            if process.leaderLiveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wasFailed {
                process.leaderLiveSummary = "The internal Agent council is complete. Finishing the final answer from accepted findings."
            }
            if process.recentUpdateItems.contains(where: { $0.kind == .councilCompleted }) == false {
                process.recentUpdateItems.insert(
                    AgentProcessUpdate(
                        kind: .councilCompleted,
                        source: .leader,
                        phase: .completed,
                        summary: "Council completed."
                    ),
                    at: 0
                )
            }
            process.recentUpdates = process.recentUpdateItems.map(\.summary)
            return process
        }

        process.activity = phase.compatibilityActivity
        process.stopReason = nil
        process.outcome = ""
        process.currentFocus = fallbackFocus(for: phase, processSnapshot: process)
        if process.leaderAcceptedFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.leaderAcceptedFocus = process.currentFocus
        }
        if process.leaderLiveStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wasFailed {
            process.leaderLiveStatus = fallbackStatus(for: phase, processSnapshot: process)
        }
        if process.leaderLiveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wasFailed {
            process.leaderLiveSummary = fallbackSummary(for: phase, processSnapshot: process)
        }
        if phase == .workerWave {
            process.tasks = restoredWorkerTasks(
                for: snapshot,
                conversation: conversation,
                focus: process.currentFocus
            )
            process.activeTaskIDs = process.tasks
                .filter { $0.status == .queued || $0.status == .running }
                .map(\.id)
        }
        process.recentUpdates = process.recentUpdateItems.map(\.summary)
        return process
    }

    func backfillCheckpointBaseResponseIDs(
        on snapshot: inout AgentRunSnapshot,
        in conversation: Conversation
    ) {
        snapshot.leaderTicket = backfilledCheckpointBaseResponseID(
            on: snapshot.leaderTicket,
            role: .leader,
            in: conversation
        )
        snapshot.workerATicket = backfilledCheckpointBaseResponseID(
            on: snapshot.workerATicket,
            role: .workerA,
            in: conversation
        )
        snapshot.workerBTicket = backfilledCheckpointBaseResponseID(
            on: snapshot.workerBTicket,
            role: .workerB,
            in: conversation
        )
        snapshot.workerCTicket = backfilledCheckpointBaseResponseID(
            on: snapshot.workerCTicket,
            role: .workerC,
            in: conversation
        )
    }

    func backfilledCheckpointBaseResponseID(
        on ticket: AgentRunTicket?,
        role: AgentRole,
        in conversation: Conversation
    ) -> AgentRunTicket? {
        guard var ticket else { return nil }
        let existingCheckpointBase = ticket.checkpointBaseResponseID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard existingCheckpointBase == nil || existingCheckpointBase?.isEmpty == true else {
            return ticket
        }

        let candidate = conversation.agentConversationState?
            .responseID(for: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let candidate, !candidate.isEmpty, candidate != ticket.responseID else {
            return ticket
        }

        ticket.checkpointBaseResponseID = candidate
        return ticket
    }
}
