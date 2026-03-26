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
        var lastEventID: String?
        for task in tasks {
            let event = AgentEvent(
                kind: .taskQueued,
                summary: "Queued \(task.owner.displayName): \(task.title)"
            )
            snapshot.processSnapshot.events.append(event)
            lastEventID = event.id
        }
        updateTaskBookkeeping(
            queuedCount: tasks.count,
            sourceEventID: lastEventID,
            on: &snapshot
        )
    }

    static func queueTasks(
        _ tasks: [AgentTask],
        on snapshot: inout AgentRunSnapshot
    ) {
        var lastEventID: String?
        for task in tasks {
            snapshot.processSnapshot.tasks.append(task)
            let event = AgentEvent(
                kind: .taskQueued,
                summary: "Queued \(task.owner.displayName): \(task.title)"
            )
            snapshot.processSnapshot.events.append(event)
            lastEventID = event.id
        }
        snapshot.processSnapshot.activeTaskIDs = snapshot.processSnapshot.tasks
            .filter { $0.status == .running }
            .map(\.id)
        updateTaskBookkeeping(
            queuedCount: tasks.count,
            sourceEventID: lastEventID,
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
        let event = AgentEvent(
            kind: .taskStarted,
            summary: "Started \(snapshot.processSnapshot.tasks[index].title)"
        )
        snapshot.processSnapshot.events.append(event)
        updateTaskBookkeeping(
            queuedCount: nil,
            sourceEventID: event.id,
            on: &snapshot
        )
        if snapshot.processSnapshot.tasks[index].owner.role != nil {
            let workerStartedSummary =
                "\(snapshot.processSnapshot.tasks[index].owner.displayName) "
                    + "started \(snapshot.processSnapshot.tasks[index].title)."
            AgentRecentUpdateProjector.recordWorkerMilestone(
                kind: .workerStarted,
                task: snapshot.processSnapshot.tasks[index],
                sourceEventID: event.id,
                summary: workerStartedSummary,
                on: &snapshot
            )
        }
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
        let event = AgentEvent(
            kind: status == .completed ? .taskCompleted : .taskFailed,
            summary: "\(snapshot.processSnapshot.tasks[index].title) \(status.displayName.lowercased())"
        )
        snapshot.processSnapshot.events.append(event)
        snapshot.processSnapshot.evidence.append(
            contentsOf: AgentSummaryFormatter.summarizeBullets(
                result.evidence,
                maxItems: 1,
                maxLength: 96
            )
        )
        updateTaskBookkeeping(
            queuedCount: nil,
            sourceEventID: event.id,
            on: &snapshot
        )
        if snapshot.processSnapshot.tasks[index].owner.role != nil {
            AgentRecentUpdateProjector.recordWorkerMilestone(
                kind: status == .completed ? .workerCompleted : .workerFailed,
                task: snapshot.processSnapshot.tasks[index],
                sourceEventID: event.id,
                summary: "\(snapshot.processSnapshot.tasks[index].owner.displayName) \(status.displayName.lowercased()).",
                on: &snapshot
            )
        }
    }
}

private extension AgentProcessProjector {
    static func updateTaskBookkeeping(
        queuedCount: Int?,
        sourceEventID: String?,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.updatedAt = .now
        snapshot.lastCheckpointAt = .now
        snapshot.processSnapshot.updatedAt = .now
        if let queuedCount {
            AgentRecentUpdateProjector.recordWorkerWaveQueued(
                count: queuedCount,
                sourceEventID: sourceEventID,
                on: &snapshot
            )
        }
        syncLegacyWorkerProgress(on: &snapshot)
    }
}
