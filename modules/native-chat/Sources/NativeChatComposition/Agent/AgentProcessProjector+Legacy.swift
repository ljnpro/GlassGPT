import ChatDomain
import Foundation

extension AgentProcessProjector {
    static func finalize(
        outcome: String,
        stopReason: AgentStopReason,
        activity: AgentProcessActivity,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.activity = activity
        snapshot.processSnapshot.stopReason = stopReason
        snapshot.processSnapshot.outcome = outcome
        snapshot.processSnapshot.activeTaskIDs = []
        snapshot.processSnapshot.events.append(
            AgentEvent(
                kind: activity == .completed ? .completed : .failed,
                summary: outcome
            )
        )
        snapshot.currentStage = activity == .completed
            ? .finalSynthesis
            : (legacyStage(for: activity) ?? .finalSynthesis)
        snapshot.updatedAt = .now
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
