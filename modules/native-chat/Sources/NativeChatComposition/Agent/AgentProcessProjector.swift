import ChatDomain
import Foundation

@MainActor
enum AgentProcessProjector {}

extension AgentProcessProjector {
    static func makeInitialRunSnapshot(
        draftMessageID: UUID,
        latestUserMessageID: UUID,
        configuration: AgentConversationConfiguration = AgentConversationConfiguration()
    ) -> AgentRunSnapshot {
        let startedEvent = AgentEvent(kind: .started, summary: "Started Agent run")

        return AgentRunSnapshot(
            currentStage: .leaderBrief,
            phase: .leaderTriage,
            draftMessageID: draftMessageID,
            latestUserMessageID: latestUserMessageID,
            runConfiguration: configuration,
            processSnapshot: AgentProcessSnapshot(
                activity: .triage,
                currentFocus: "Leader is scoping the request.",
                leaderAcceptedFocus: "Leader is scoping the request.",
                leaderLiveStatus: "Scoping the request",
                leaderLiveSummary: "Classifying the request and sketching the first plan.",
                events: [startedEvent],
                recentUpdateItems: [
                    AgentProcessUpdate(
                        kind: .runStarted,
                        source: .system,
                        phase: .leaderTriage,
                        sourceEventID: startedEvent.id,
                        summary: "Started Agent run"
                    )
                ]
            )
        )
    }

    static func prepareForResume(_ snapshot: inout AgentRunSnapshot) {
        for index in snapshot.processSnapshot.tasks.indices
            where snapshot.processSnapshot.tasks[index].status == .running {
            if snapshot.ticket(for: snapshot.processSnapshot.tasks[index].owner.role ?? .leader)?.responseID == nil {
                snapshot.processSnapshot.tasks[index].status = .queued
            }
        }
        snapshot.processSnapshot.activeTaskIDs = snapshot.processSnapshot.tasks
            .filter { $0.status == .running }
            .map(\.id)
        snapshot.currentStage = legacyStage(for: snapshot.processSnapshot.activity) ?? snapshot.phase.compatibilityStage
        snapshot.processSnapshot.recoveryState = .idle
        syncLegacyWorkerProgress(on: &snapshot)
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        AgentRecentUpdateProjector.sanitizeRecentUpdates(on: &snapshot)
    }

    static func updateFocus(
        _ focus: String,
        activity: AgentProcessActivity,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.activity = activity
        snapshot.processSnapshot.currentFocus = focus
        snapshot.processSnapshot.leaderAcceptedFocus = focus
        if snapshot.processSnapshot.leaderLiveSummary.isEmpty {
            snapshot.processSnapshot.leaderLiveSummary = focus
        }
        let event = AgentEvent(kind: .focusUpdated, summary: focus)
        snapshot.processSnapshot.events.append(event)
        snapshot.currentStage = legacyStage(for: activity) ?? .leaderBrief
        snapshot.phase = phase(for: activity)
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
    }
}

extension AgentProcessProjector {
    static func updateLeaderLivePreview(
        status: String?,
        summary: String?,
        on snapshot: inout AgentRunSnapshot
    ) {
        if let status {
            snapshot.processSnapshot.leaderLiveStatus = AgentSummaryFormatter.summarize(status, maxLength: 40)
        }
        if let summary {
            snapshot.processSnapshot.leaderLiveSummary = AgentSummaryFormatter.summarize(summary, maxLength: 96)
        }
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    static func updateRecoveryState(
        _ recoveryState: AgentRecoveryState,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.recoveryState = recoveryState
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        AgentRecentUpdateProjector.updateRecoveryMilestone(recoveryState, on: &snapshot)
    }

    static func updatePhase(
        _ phase: AgentRunPhase,
        leaderStatus: String? = nil,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.phase = phase
        snapshot.currentStage = phase.compatibilityStage
        snapshot.processSnapshot.activity = phase.compatibilityActivity
        if let leaderStatus {
            snapshot.processSnapshot.leaderLiveStatus = leaderStatus
        } else {
            snapshot.processSnapshot.leaderLiveStatus = phase.displayName
        }
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    static func replacePlan(
        _ plan: [AgentPlanStep],
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.plan = plan
        let event = AgentEvent(kind: .planUpdated, summary: "Updated Agent plan")
        snapshot.processSnapshot.events.append(event)
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        AgentRecentUpdateProjector.recordPlanMilestone(
            "Updated plan",
            phase: snapshot.phase,
            sourceEventID: event.id,
            on: &snapshot
        )
    }

    static func appendDecision(
        kind: AgentDecisionKind,
        title: String,
        summary: String,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.decisions.append(
            AgentDecision(kind: kind, title: title, summary: summary)
        )
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .decisionRecorded, summary: summary)
        )
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    static func appendEvidence(
        _ evidence: [String],
        on snapshot: inout AgentRunSnapshot
    ) {
        let trimmed = AgentSummaryFormatter.summarizeBullets(
            evidence.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty },
            maxItems: 3,
            maxLength: 96
        )
        guard !trimmed.isEmpty else { return }
        snapshot.processSnapshot.evidence.append(contentsOf: trimmed)
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .evidenceRecorded, summary: "Added \(trimmed.count) evidence item(s)")
        )
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    private static func phase(for activity: AgentProcessActivity) -> AgentRunPhase {
        switch activity {
        case .triage:
            .leaderTriage
        case .localPass:
            .leaderLocalPass
        case .delegation:
            .workerWave
        case .reviewing:
            .leaderReview
        case .synthesis:
            .finalSynthesis
        case .waitingForUser, .completed:
            .completed
        case .failed:
            .failed
        }
    }
}
