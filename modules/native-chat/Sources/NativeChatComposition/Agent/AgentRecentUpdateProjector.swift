import ChatDomain
import Foundation

@MainActor
enum AgentRecentUpdateProjector {
    static func recordLeaderPhaseMilestone(
        _ summary: String,
        phase: AgentRunPhase,
        sourceEventID: String? = nil,
        on snapshot: inout AgentRunSnapshot
    ) {
        let update = AgentProcessUpdate(
            kind: .leaderPhase,
            source: .leader,
            phase: phase,
            sourceEventID: sourceEventID,
            summary: summary
        )
        upsertRecentUpdate(
            update,
            replacing: { existing in
                existing.kind == .leaderPhase &&
                    existing.source == .leader
            },
            on: &snapshot.processSnapshot
        )
    }

    static func recordPlanMilestone(
        _ summary: String,
        phase: AgentRunPhase,
        sourceEventID: String? = nil,
        on snapshot: inout AgentRunSnapshot
    ) {
        let update = AgentProcessUpdate(
            kind: .planUpdated,
            source: .leader,
            phase: phase,
            sourceEventID: sourceEventID,
            summary: summary
        )
        upsertRecentUpdate(
            update,
            replacing: { existing in
                existing.kind == .planUpdated
            },
            on: &snapshot.processSnapshot
        )
    }

    static func recordWorkerWaveQueued(
        count: Int,
        sourceEventID: String? = nil,
        on snapshot: inout AgentRunSnapshot
    ) {
        let update = AgentProcessUpdate(
            kind: .workerWaveQueued,
            source: .leader,
            phase: .workerWave,
            sourceEventID: sourceEventID,
            summary: "Queued \(count) worker task(s)."
        )
        upsertRecentUpdate(
            update,
            replacing: { existing in
                existing.kind == .workerWaveQueued
            },
            on: &snapshot.processSnapshot
        )
    }

    static func recordWorkerMilestone(
        kind: AgentProcessUpdateKind,
        task: AgentTask,
        sourceEventID: String? = nil,
        summary: String,
        on snapshot: inout AgentRunSnapshot
    ) {
        let update = AgentProcessUpdate(
            kind: kind,
            source: AgentProcessUpdateSource(role: task.owner.role),
            phase: .workerWave,
            taskID: task.id,
            sourceEventID: sourceEventID,
            summary: summary
        )
        upsertRecentUpdate(
            update,
            replacing: { existing in
                switch kind {
                case .workerStarted:
                    existing.source == update.source &&
                        (existing.kind == .workerStarted ||
                            existing.kind == .workerCompleted ||
                            existing.kind == .workerFailed)
                case .workerCompleted, .workerFailed:
                    existing.source == update.source &&
                        (existing.kind == .workerStarted || existing.kind == .workerCompleted || existing.kind == .workerFailed)
                default:
                    false
                }
            },
            on: &snapshot.processSnapshot
        )
    }

    static func recordCouncilCompleted(
        _ summary: String,
        sourceEventID: String? = nil,
        on snapshot: inout AgentRunSnapshot
    ) {
        let update = AgentProcessUpdate(
            kind: .councilCompleted,
            source: .leader,
            phase: .completed,
            sourceEventID: sourceEventID,
            summary: summary
        )
        upsertRecentUpdate(
            update,
            replacing: { existing in
                existing.kind == .councilCompleted
            },
            on: &snapshot.processSnapshot
        )
    }

    static func updateRecoveryMilestone(
        _ recoveryState: AgentRecoveryState,
        on snapshot: inout AgentRunSnapshot
    ) {
        switch recoveryState {
        case .idle:
            snapshot.processSnapshot.recentUpdateItems.removeAll { $0.kind == .recovery || $0.source == .recovery }
            syncLegacyRecentUpdates(on: &snapshot.processSnapshot)
        case .reconnecting, .replayingCheckpoint:
            let update = AgentProcessUpdate(
                kind: .recovery,
                source: .recovery,
                phase: snapshot.phase,
                summary: recoveryState.displayName
            )
            upsertRecentUpdate(
                update,
                replacing: { existing in
                    existing.kind == .recovery || existing.source == .recovery
                },
                on: &snapshot.processSnapshot
            )
        }
    }

    static func compactRecentUpdates(on snapshot: inout AgentRunSnapshot) {
        compactRecentUpdates(on: &snapshot.processSnapshot)
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }
}
