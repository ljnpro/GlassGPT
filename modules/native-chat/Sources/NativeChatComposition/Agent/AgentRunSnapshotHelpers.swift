import ChatDomain
import Foundation

extension AgentRunCoordinator {
    func currentCompletedTasks(from snapshot: AgentRunSnapshot) -> [AgentTask] {
        let completedTasks = snapshot.processSnapshot.tasks.filter {
            $0.status == .completed || $0.status == .failed
        }
        if !completedTasks.isEmpty {
            return completedTasks
        }

        let legacySummaries = snapshot.crossReviewSummaries.isEmpty
            ? snapshot.workersRoundOneSummaries
            : snapshot.crossReviewSummaries
        guard !legacySummaries.isEmpty else {
            return []
        }

        let contextSummary = snapshot.processSnapshot.currentFocus.isEmpty
            ? (snapshot.leaderBriefSummary ?? "Recovered worker summary")
            : snapshot.processSnapshot.currentFocus

        return legacySummaries.map { workerSummary in
            AgentTask(
                id: "legacy-\(workerSummary.role.rawValue)",
                owner: AgentTaskOwner(rawValue: workerSummary.role.rawValue) ?? .workerA,
                title: "\(workerSummary.role.displayName) summary",
                goal: workerSummary.summary,
                expectedOutput: "Compact worker summary",
                contextSummary: contextSummary,
                toolPolicy: .enabled,
                status: .completed,
                resultSummary: workerSummary.summary,
                result: AgentTaskResult(
                    summary: workerSummary.summary,
                    evidence: workerSummary.adoptedPoints
                ),
                completedAt: snapshot.updatedAt
            )
        }
    }

    func currentQueuedTasks(from snapshot: AgentRunSnapshot) -> [AgentTask] {
        snapshot.processSnapshot.tasks.filter { $0.status == .queued || $0.status == .running }
    }

    func pendingTasksToRun(from tasks: [AgentTask]) -> [AgentTask] {
        tasks.map { task in
            var task = task
            task.status = .queued
            return task
        }
    }

    func latestDecisionSummary(in snapshot: AgentRunSnapshot) -> String {
        snapshot.processSnapshot.decisions.last?.summary ?? snapshot.processSnapshot.currentFocus
    }

    func updatedTask(for taskID: String, in snapshot: AgentRunSnapshot) -> AgentTask? {
        snapshot.processSnapshot.tasks.first(where: { $0.id == taskID })
    }

    func markPlanStepCompleted(for task: AgentTask, on snapshot: inout AgentRunSnapshot) {
        guard let stepID = task.parentStepID,
              let index = snapshot.processSnapshot.plan.firstIndex(where: { $0.id == stepID })
        else {
            return
        }

        snapshot.processSnapshot.plan[index].status = .completed
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    func mappedStopReason(
        decision: AgentTaggedOutputParser.LeaderDecision,
        stopReasonText: String?
    ) -> AgentStopReason {
        if decision == .clarify {
            return .clarificationRequired
        }

        let text = (stopReasonText ?? "").lowercased()
        if text.contains("budget") || text.contains("limit") {
            return .budgetReached
        }
        if text.contains("tool") || text.contains("search") || text.contains("code") {
            return .toolFailure
        }
        return .sufficientAnswer
    }

    func forceBudgetStopDirective(
        from directive: AgentTaggedOutputParser.LeaderDirective,
        focus: String
    ) -> AgentTaggedOutputParser.LeaderDirective {
        AgentTaggedOutputParser.LeaderDirective(
            focus: focus,
            decision: .finish,
            plan: directive.plan,
            tasks: [],
            decisionNote: "The leader stopped after enough task waves.",
            stopReason: "Budget limit reached; synthesize the best answer from current evidence."
        )
    }
}
