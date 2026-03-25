import ChatDomain
import Foundation

@MainActor
enum AgentProcessProjector {
    static func makeInitialRunSnapshot(
        draftMessageID: UUID,
        latestUserMessageID: UUID
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            currentStage: .leaderBrief,
            draftMessageID: draftMessageID,
            latestUserMessageID: latestUserMessageID,
            processSnapshot: AgentProcessSnapshot(
                activity: .triage,
                currentFocus: "Leader is planning the work.",
                events: [
                    AgentEvent(kind: .started, summary: "Started Agent run")
                ]
            )
        )
    }

    static func prepareForResume(_ snapshot: inout AgentRunSnapshot) {
        for index in snapshot.processSnapshot.tasks.indices where snapshot.processSnapshot.tasks[index].status == .running {
            snapshot.processSnapshot.tasks[index].status = .queued
        }
        snapshot.processSnapshot.activeTaskIDs = snapshot.processSnapshot.tasks
            .filter { $0.status == .running }
            .map(\.id)
        snapshot.currentStage = legacyStage(for: snapshot.processSnapshot.activity) ?? .leaderBrief
        syncLegacyWorkerProgress(on: &snapshot)
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    static func updateFocus(
        _ focus: String,
        activity: AgentProcessActivity,
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.activity = activity
        snapshot.processSnapshot.currentFocus = focus
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .focusUpdated, summary: focus)
        )
        snapshot.currentStage = legacyStage(for: activity) ?? .leaderBrief
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
    }

    static func replacePlan(
        _ plan: [AgentPlanStep],
        on snapshot: inout AgentRunSnapshot
    ) {
        snapshot.processSnapshot.plan = plan
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .planUpdated, summary: "Updated Agent plan")
        )
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
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
        snapshot.processSnapshot.updatedAt = .now
    }

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
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
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
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
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
        if !snapshot.processSnapshot.activeTaskIDs.contains(taskID) {
            snapshot.processSnapshot.activeTaskIDs.append(taskID)
        }
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .taskStarted, summary: "Started \(snapshot.processSnapshot.tasks[index].title)")
        )
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
        snapshot.processSnapshot.tasks[index].resultSummary = result.summary
        snapshot.processSnapshot.tasks[index].completedAt = .now
        snapshot.processSnapshot.activeTaskIDs.removeAll { $0 == taskID }
        snapshot.processSnapshot.events.append(
            AgentEvent(
                kind: status == .completed ? .taskCompleted : .taskFailed,
                summary: "\(snapshot.processSnapshot.tasks[index].title) \(status.displayName.lowercased())"
            )
        )
        snapshot.processSnapshot.evidence.append(contentsOf: result.evidence)
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
    }

    static func appendEvidence(
        _ evidence: [String],
        on snapshot: inout AgentRunSnapshot
    ) {
        let trimmed = evidence.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }
        snapshot.processSnapshot.evidence.append(contentsOf: trimmed)
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .evidenceRecorded, summary: "Added \(trimmed.count) evidence item(s)")
        )
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    static func beginSynthesis(on snapshot: inout AgentRunSnapshot) {
        snapshot.processSnapshot.activity = .synthesis
        snapshot.currentStage = .finalSynthesis
        snapshot.processSnapshot.events.append(
            AgentEvent(kind: .synthesisStarted, summary: "Leader began final synthesis")
        )
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
        syncLegacyWorkerProgress(on: &snapshot)
    }

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

    private static func syncLegacyWorkerProgress(on snapshot: inout AgentRunSnapshot) {
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
