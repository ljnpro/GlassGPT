import ChatDomain
import Foundation

@MainActor
extension AgentProcessProjector {
    static func setTasks(
        _ tasks: [AgentTask],
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.tasks = tasks
        snapshot.processSnapshot.activeTaskIDs = tasks
            .filter { $0.status == .running }
            .map(\.id)
        for task in tasks {
            snapshot.processSnapshot.events.append(
                AgentEvent(
                    kind: .taskQueued,
                    summary: "Queued \(task.owner.displayName): \(task.title)"
                )
            )
        }
        updateTaskBookkeeping(
            queuedSummary: "Queued \(tasks.count) worker task(s)",
            on: &snapshot
        )
    }

    static func queueTasks(
        _ tasks: [AgentTask],
        on snapshot: inout AgentRunSnapshot
    ) {
        for task in tasks {
            snapshot.processSnapshot.tasks.append(task)
            snapshot.processSnapshot.events.append(
                AgentEvent(
                    kind: .taskQueued,
                    summary: "Queued \(task.owner.displayName): \(task.title)"
                )
            )
        }
        snapshot.processSnapshot.activeTaskIDs = snapshot.processSnapshot.tasks
            .filter { $0.status == .running }
            .map(\.id)
        updateTaskBookkeeping(
            queuedSummary: "Queued \(tasks.count) worker task(s)",
            on: &snapshot
        )
    }

    static func markTaskRunning(
        _ taskID: String,
        on snapshot: inout AgentRunSnapshot
    ) {
        guard let index = snapshot.processSnapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        snapshot.processSnapshot.tasks[index].status = .running
        snapshot.processSnapshot.tasks[index].startedAt = .now
        snapshot.processSnapshot.tasks[index].liveStatusText = "Starting"
        snapshot.processSnapshot.tasks[index].liveSummary = nil
        snapshot.processSnapshot.tasks[index].liveEvidence = []
        snapshot.processSnapshot.tasks[index].liveConfidence = nil
        snapshot.processSnapshot.tasks[index].liveRisks = []
        if !snapshot.processSnapshot.activeTaskIDs.contains(taskID) {
            snapshot.processSnapshot.activeTaskIDs.append(taskID)
        }
        snapshot.processSnapshot.events.append(
            AgentEvent(
                kind: .taskStarted,
                summary: "Started \(snapshot.processSnapshot.tasks[index].title)"
            )
        )
        updateTaskBookkeeping(
            queuedSummary: "Started \(snapshot.processSnapshot.tasks[index].owner.displayName)",
            on: &snapshot
        )
    }

    static func updateTaskLivePreview(
        taskID: String,
        statusText: String?,
        summary: String?,
        evidence: [String],
        confidence: AgentConfidence?,
        risks: [String],
        on snapshot: inout AgentRunSnapshot
    ) {
        guard let index = snapshot.processSnapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        snapshot.processSnapshot.tasks[index].liveStatusText = statusText
        snapshot.processSnapshot.tasks[index].liveSummary = summary
        snapshot.processSnapshot.tasks[index].liveEvidence = evidence
        snapshot.processSnapshot.tasks[index].liveConfidence = confidence
        snapshot.processSnapshot.tasks[index].liveRisks = risks
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
        if let summary, !summary.isEmpty {
            appendRecentUpdate(
                "\(snapshot.processSnapshot.tasks[index].owner.displayName): \(summary)",
                on: &snapshot.processSnapshot
            )
        }
        syncLegacyWorkerProgress(on: &snapshot)
    }

    static func recordTaskResult(
        _ result: AgentTaskResult,
        for taskID: String,
        status: AgentTaskStatus,
        on snapshot: inout AgentRunSnapshot
    ) {
        guard let index = snapshot.processSnapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        snapshot.processSnapshot.tasks[index].status = status
        snapshot.processSnapshot.tasks[index].result = result
        snapshot.processSnapshot.tasks[index].resultSummary = AgentSummaryFormatter.summarize(
            result.summary,
            maxLength: 150
        )
        snapshot.processSnapshot.tasks[index].liveStatusText = nil
        snapshot.processSnapshot.tasks[index].liveSummary = nil
        snapshot.processSnapshot.tasks[index].liveEvidence = []
        snapshot.processSnapshot.tasks[index].liveConfidence = nil
        snapshot.processSnapshot.tasks[index].liveRisks = []
        snapshot.processSnapshot.tasks[index].completedAt = .now
        snapshot.processSnapshot.activeTaskIDs.removeAll { $0 == taskID }
        snapshot.processSnapshot.events.append(
            AgentEvent(
                kind: status == .completed ? .taskCompleted : .taskFailed,
                summary: "\(snapshot.processSnapshot.tasks[index].title) \(status.displayName.lowercased())"
            )
        )
        snapshot.processSnapshot.evidence.append(
            contentsOf: AgentSummaryFormatter.summarizeBullets(
                result.evidence,
                maxItems: 1,
                maxLength: 96
            )
        )
        updateTaskBookkeeping(
            queuedSummary: """
            \(snapshot.processSnapshot.tasks[index].owner.displayName) \
            \(status.displayName.lowercased())
            """,
            on: &snapshot
        )
    }
}

private extension AgentProcessProjector {
    static func updateTaskBookkeeping(
        queuedSummary: String,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        appendRecentUpdate(queuedSummary, on: &snapshot.processSnapshot)
        syncLegacyWorkerProgress(on: &snapshot)
    }
}
