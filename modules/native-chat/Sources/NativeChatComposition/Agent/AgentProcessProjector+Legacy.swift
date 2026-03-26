import ChatDomain
import Foundation

extension AgentProcessProjector {
    static func finalize(
        outcome: String,
        stopReason: AgentStopReason,
        activity: AgentProcessActivity,
        on snapshot: inout AgentRunSnapshot
    ) {
        let previousStage = snapshot.currentStage
        snapshot.processSnapshot.activity = activity
        snapshot.processSnapshot.stopReason = stopReason
        snapshot.processSnapshot.outcome = outcome
        snapshot.processSnapshot.activeTaskIDs = []
        snapshot.processSnapshot.leaderLiveStatus = switch activity {
        case .completed, .waitingForUser:
            "Done"
        default:
            activity.displayName
        }
        snapshot.processSnapshot.leaderLiveSummary = ""
        snapshot.processSnapshot.recoveryState = .idle
        let event = AgentEvent(
            kind: activity == .completed ? .completed : .failed,
            summary: outcome
        )
        snapshot.processSnapshot.events.append(event)
        if activity == .completed {
            snapshot.currentStage = .finalSynthesis
        } else if activity == .failed {
            snapshot.currentStage = previousStage
        } else {
            snapshot.currentStage = legacyStage(for: activity) ?? .finalSynthesis
        }
        switch activity {
        case .completed, .waitingForUser:
            snapshot.phase = .completed
        case .failed:
            snapshot.phase = .failed
        case .triage:
            snapshot.phase = .leaderTriage
        case .localPass:
            snapshot.phase = .leaderLocalPass
        case .delegation:
            snapshot.phase = .workerWave
        case .reviewing:
            snapshot.phase = .leaderReview
        case .synthesis:
            snapshot.phase = .finalSynthesis
        }
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        if activity == .completed || activity == .waitingForUser {
            AgentRecentUpdateProjector.recordCouncilCompleted(
                "Council completed.",
                sourceEventID: event.id,
                on: &snapshot
            )
        }
        syncLegacyWorkerProgress(on: &snapshot)
    }

    static func freezeCouncilForVisibleSynthesis(on snapshot: inout AgentRunSnapshot) {
        let acceptedFocus = snapshot.processSnapshot.leaderAcceptedFocus
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFocus = snapshot.processSnapshot.currentFocus
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFocus = acceptedFocus.isEmpty
            ? (currentFocus.isEmpty ? "Leader completed the internal Agent council." : currentFocus)
            : acceptedFocus

        if snapshot.processSnapshot.activity != .waitingForUser, snapshot.processSnapshot.activity != .completed {
            snapshot.processSnapshot.activity = .completed
        }
        snapshot.processSnapshot.currentFocus = resolvedFocus
        snapshot.processSnapshot.leaderAcceptedFocus = resolvedFocus
        snapshot.processSnapshot.leaderLiveStatus = "Done"
        snapshot.processSnapshot.activeTaskIDs = []
        snapshot.processSnapshot.recoveryState = .idle
        if snapshot.processSnapshot.recentUpdateItems.contains(where: { $0.kind == .councilCompleted }) == false {
            AgentRecentUpdateProjector.recordCouncilCompleted(
                "Council completed.",
                on: &snapshot
            )
        }
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
    }

    static func legacyStage(for activity: AgentProcessActivity) -> AgentStage? {
        switch activity {
        case .triage, .localPass:
            .leaderBrief
        case .delegation:
            .workersRoundOne
        case .reviewing:
            .crossReview
        case .synthesis, .waitingForUser, .completed, .failed:
            .finalSynthesis
        }
    }

    static func syncLegacyWorkerProgress(on snapshot: inout AgentRunSnapshot) {
        let workerTasks = snapshot.processSnapshot.tasks.filter { $0.owner.role != nil }
        let progress = [AgentRole.workerA, .workerB, .workerC].map { role in
            let status = workerTasks.last(where: { $0.owner.role == role }).map(progressStatus(for:)) ?? .waiting
            return AgentWorkerProgress(role: role, status: status)
        }

        switch snapshot.processSnapshot.activity {
        case .delegation:
            snapshot.workersRoundOneProgress = progress
        case .reviewing:
            snapshot.crossReviewProgress = progress
        default:
            break
        }
    }

    private static func progressStatus(for task: AgentTask) -> AgentWorkerProgress.Status {
        switch task.status {
        case .queued:
            .waiting
        case .running:
            .running
        case .completed:
            .completed
        case .blocked, .failed, .discarded:
            .failed
        }
    }
}
