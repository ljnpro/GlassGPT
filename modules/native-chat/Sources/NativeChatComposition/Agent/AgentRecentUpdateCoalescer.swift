import ChatDomain
import Foundation

extension AgentRecentUpdateProjector {
    static func sanitizeRecentUpdates(on snapshot: inout AgentRunSnapshot) {
        let semanticItems = snapshot.processSnapshot.recentUpdateItems.filter { $0.kind != .legacy }
        if !semanticItems.isEmpty {
            snapshot.processSnapshot.recentUpdateItems = semanticItems
        } else if !snapshot.processSnapshot.recentUpdateItems.isEmpty {
            snapshot.processSnapshot.recentUpdateItems = rebuiltSemanticUpdates(from: snapshot)
        }

        compactRecentUpdates(on: &snapshot.processSnapshot)
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    static func upsertRecentUpdate(
        _ update: AgentProcessUpdate,
        replacing predicate: (AgentProcessUpdate) -> Bool,
        on process: inout AgentProcessSnapshot
    ) {
        var normalizedUpdate = normalized(update)
        normalizedUpdate.updatedAt = .now
        guard !normalizedUpdate.summary.isEmpty else { return }

        process.recentUpdateItems.removeAll(where: predicate)
        process.recentUpdateItems.removeAll { existing in
            normalized(existing).summary == normalizedUpdate.summary &&
                coalescingKey(for: existing) == coalescingKey(for: normalizedUpdate)
        }
        process.recentUpdateItems.insert(normalizedUpdate, at: 0)
        compactRecentUpdates(on: &process)
    }

    static func compactRecentUpdates(on process: inout AgentProcessSnapshot) {
        let semanticItems = process.recentUpdateItems.filter { $0.kind != .legacy }
        let sourceItems = semanticItems.isEmpty ? process.recentUpdateItems : semanticItems
        let sorted = sourceItems
            .map(normalized)
            .filter { !$0.summary.isEmpty }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }

        var compacted: [AgentProcessUpdate] = []
        var seenKeys: Set<String> = []
        var seenSummaryKeys: Set<String> = []
        compacted.reserveCapacity(min(sorted.count, 5))

        for update in sorted {
            let semanticKey = coalescingKey(for: update)
            let summaryKey = "\(update.source.rawValue)|\(canonicalSummary(update.summary))"
            if seenKeys.contains(semanticKey) || seenSummaryKeys.contains(summaryKey) {
                continue
            }
            compacted.append(update)
            seenKeys.insert(semanticKey)
            seenSummaryKeys.insert(summaryKey)
            if compacted.count == 5 {
                break
            }
        }

        process.recentUpdateItems = compacted
        syncLegacyRecentUpdates(on: &process)
    }

    static func syncLegacyRecentUpdates(on process: inout AgentProcessSnapshot) {
        process.recentUpdates = process.recentUpdateItems.map(\.summary)
    }

    static func rebuiltSemanticUpdates(from snapshot: AgentRunSnapshot) -> [AgentProcessUpdate] {
        let process = snapshot.processSnapshot
        var updates: [AgentProcessUpdate] = []

        let startedAt = process.events.first(where: { $0.kind == .started })?.createdAt ?? process.updatedAt
        updates.append(
            AgentProcessUpdate(
                kind: .runStarted,
                source: .system,
                phase: snapshot.phase,
                summary: "Started Agent run",
                createdAt: startedAt,
                updatedAt: startedAt
            )
        )

        if let leaderMilestone = rebuiltLeaderMilestone(from: snapshot) {
            updates.append(leaderMilestone)
        }

        if !process.plan.isEmpty {
            let timestamp = process.events.last(where: { $0.kind == .planUpdated })?.createdAt ?? process.updatedAt
            updates.append(
                AgentProcessUpdate(
                    kind: .planUpdated,
                    source: .leader,
                    phase: snapshot.phase,
                    summary: "Plan updated.",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }

        if !process.tasks.isEmpty {
            let timestamp = process.events.last(where: { $0.kind == .taskQueued })?.createdAt ?? process.updatedAt
            updates.append(
                AgentProcessUpdate(
                    kind: .workerWaveQueued,
                    source: .leader,
                    phase: .workerWave,
                    summary: "Queued \(process.tasks.count) worker task(s).",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }

        updates.append(contentsOf: rebuiltWorkerMilestones(from: snapshot))

        if process.activity == .completed || process.activity == .waitingForUser || snapshot.phase == .finalSynthesis {
            let timestamp = process.events.last(where: { $0.kind == .completed })?.createdAt ?? process.updatedAt
            updates.append(
                AgentProcessUpdate(
                    kind: .councilCompleted,
                    source: .leader,
                    phase: .completed,
                    summary: "Council completed.",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }

        if process.recoveryState != .idle {
            updates.append(
                AgentProcessUpdate(
                    kind: .recovery,
                    source: .recovery,
                    phase: snapshot.phase,
                    summary: process.recoveryState.displayName,
                    createdAt: process.updatedAt,
                    updatedAt: process.updatedAt
                )
            )
        }

        return updates
    }

    static func normalized(_ update: AgentProcessUpdate) -> AgentProcessUpdate {
        var normalized = update
        normalized.summary = AgentSummaryFormatter.summarize(
            normalized.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            maxLength: 72
        )
        return normalized
    }

    static func coalescingKey(for update: AgentProcessUpdate) -> String {
        switch update.kind {
        case .runStarted:
            "runStarted"
        case .leaderPhase:
            "leaderPhase:\(update.source.rawValue)"
        case .planUpdated:
            "planUpdated"
        case .workerWaveQueued:
            "workerWaveQueued"
        case .workerStarted:
            "workerStarted:\(update.source.rawValue)"
        case .workerCompleted, .workerFailed:
            "workerTerminal:\(update.source.rawValue)"
        case .councilCompleted:
            "councilCompleted"
        case .recovery:
            "recovery"
        case .legacy:
            "legacy:\(canonicalSummary(update.summary))"
        }
    }

    static func canonicalSummary(_ summary: String) -> String {
        summary
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func rebuiltLeaderMilestone(from snapshot: AgentRunSnapshot) -> AgentProcessUpdate? {
        let phase = snapshot.phase
        let summary: String? = switch phase {
        case .leaderTriage:
            "Leader began triage."
        case .leaderLocalPass:
            "Leader started the local pass."
        case .leaderReview:
            "Leader began review."
        case .workerWave, .finalSynthesis, .attachmentUpload, .reconnecting, .replayingCheckpoint, .completed, .failed:
            nil
        }

        guard let summary else { return nil }
        let timestamp = snapshot.processSnapshot.events.last(where: { event in
            switch event.kind {
            case .focusUpdated, .decisionRecorded, .planUpdated:
                true
            default:
                false
            }
        })?.createdAt ?? snapshot.processSnapshot.updatedAt

        return AgentProcessUpdate(
            kind: .leaderPhase,
            source: .leader,
            phase: phase,
            summary: summary,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private static func rebuiltWorkerMilestones(from snapshot: AgentRunSnapshot) -> [AgentProcessUpdate] {
        [AgentRole.workerA, .workerB, .workerC].compactMap { role in
            let tasks = snapshot.processSnapshot.tasks
                .filter { $0.owner.role == role }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.completedAt ?? lhs.startedAt ?? snapshot.processSnapshot.updatedAt
                    let rhsDate = rhs.completedAt ?? rhs.startedAt ?? snapshot.processSnapshot.updatedAt
                    return lhsDate > rhsDate
                }

            guard let task = tasks.first else { return nil }
            let source = AgentProcessUpdateSource(role: role)
            let timestamp = task.completedAt ?? task.startedAt ?? snapshot.processSnapshot.updatedAt

            switch task.status {
            case .completed:
                return AgentProcessUpdate(
                    kind: .workerCompleted,
                    source: source,
                    phase: .workerWave,
                    taskID: task.id,
                    summary: "\(task.owner.displayName) completed.",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            case .failed, .blocked:
                return AgentProcessUpdate(
                    kind: .workerFailed,
                    source: source,
                    phase: .workerWave,
                    taskID: task.id,
                    summary: "\(task.owner.displayName) failed.",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            case .queued, .running:
                return AgentProcessUpdate(
                    kind: .workerStarted,
                    source: source,
                    phase: .workerWave,
                    taskID: task.id,
                    summary: "\(task.owner.displayName) started \(task.title).",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            case .discarded:
                return nil
            }
        }
    }
}
