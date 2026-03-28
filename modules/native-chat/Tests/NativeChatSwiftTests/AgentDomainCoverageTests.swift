import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendComposition

@Suite(.tags(.presentation))
struct AgentDomainCoverageTests {
    @Test func `agent summary formatter normalizes truncates and summarizes bullet lists`() {
        let normalized = AgentSummaryFormatter.normalizedText("  One\t\tTwo\r\n\r\n\r\nThree  ")
        #expect(normalized == "One Two\n\nThree")

        let summary = AgentSummaryFormatter.summarize(
            "Alpha beta gamma delta epsilon zeta eta theta",
            maxLength: 20
        )
        #expect(summary == "Alpha beta gamma…")

        let bullets = AgentSummaryFormatter.summarizeBullets(
            [
                "  first supporting point  ",
                "",
                "second supporting point that is much longer than allowed"
            ],
            maxItems: 2,
            maxLength: 18
        )
        #expect(bullets == ["first supporting…", "second supporting…"])
    }

    @Test func `agent summary formatter derives latest completed worker tasks and summaries`() {
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let snapshot = AgentProcessSnapshot(
            tasks: [
                AgentTask(
                    id: "a1",
                    owner: .workerA,
                    title: "Old task",
                    goal: "Goal",
                    expectedOutput: "Output",
                    contextSummary: "Context",
                    toolPolicy: .enabled,
                    status: .completed,
                    result: AgentTaskResult(
                        summary: "Early summary",
                        evidence: ["alpha", "beta", "gamma"]
                    ),
                    completedAt: earlier
                ),
                AgentTask(
                    id: "a2",
                    owner: .workerA,
                    title: "New task",
                    goal: "Goal",
                    expectedOutput: "Output",
                    contextSummary: "Context",
                    toolPolicy: .enabled,
                    status: .completed,
                    result: AgentTaskResult(
                        summary: "Latest summary",
                        evidence: ["delta", "epsilon", "zeta"]
                    ),
                    completedAt: later
                ),
                AgentTask(
                    id: "b1",
                    owner: .workerB,
                    title: "Running task",
                    goal: "Goal",
                    expectedOutput: "Output",
                    contextSummary: "Context",
                    toolPolicy: .reasoningOnly,
                    status: .running
                )
            ]
        )

        let latest = AgentSummaryFormatter.latestCompletedWorkerTask(role: .workerA, from: snapshot)
        #expect(latest?.id == "a2")

        let summaries = AgentSummaryFormatter.workerSummaries(from: snapshot)
        #expect(summaries.count == 1)
        #expect(summaries.first?.role == .workerA)
        #expect(summaries.first?.summary == "Latest summary")
        #expect(summaries.first?.adoptedPoints == ["delta", "epsilon"])
    }

    @Test func `agent process enums runtime models and configuration bridges expose expected labels`() {
        #expect(AgentTaskOwner.leader.displayName == "Leader")
        #expect(AgentTaskOwner.workerC.shortLabel == "C")
        #expect(AgentTaskOwner.workerB.role == .workerB)
        #expect(AgentTaskOwner.leader.role == nil)

        #expect(AgentPlanStepStatus.completed.displayName == "Done")
        #expect(AgentTaskStatus.failed.displayName == "Failed")
        #expect(AgentToolPolicy.reasoningOnly.displayName == "Reasoning Only")
        #expect(AgentConfidence.high.displayName == "High")
        #expect(AgentStopReason.budgetReached.displayName == "Budget reached")
        #expect(AgentProcessActivity.reviewing.displayName == "Leader review")

        #expect(AgentRunPhase.workerWave.displayName == "Worker wave")
        #expect(AgentRunPhase.workerWave.compatibilityStage == .workersRoundOne)
        #expect(AgentRunPhase.leaderReview.compatibilityActivity == .reviewing)
        #expect(AgentRunPhase.completed.isTerminal)
        #expect(!AgentRunPhase.completed.supportsAutomaticResume)
        #expect(AgentRecoveryState.replayingCheckpoint.displayName == "Replaying last checkpoint")

        var configuration = AgentConversationConfiguration()
        #expect(!configuration.flexModeEnabled)
        configuration.flexModeEnabled = true
        #expect(configuration.serviceTier == .flex)
        #expect(AgentStage.crossReview.compatibilityProcessActivity == .reviewing)
        #expect(AgentWorkerProgress.defaultProgress.map(\.role) == [.workerA, .workerB, .workerC])
    }

    @Test func `agent task and process snapshot computed displays prefer live values and legacy fallbacks`() {
        let task = AgentTask(
            id: "task_1",
            owner: .workerA,
            dependencyIDs: ["task_0"],
            title: "Investigate logs",
            goal: "Find the root cause",
            expectedOutput: "One sentence",
            contextSummary: "Tracebacks available",
            toolPolicy: .enabled,
            status: .completed,
            resultSummary: "Persisted summary",
            result: AgentTaskResult(
                summary: "Structured result",
                evidence: ["persisted evidence"],
                confidence: .medium,
                risks: ["persisted risk"]
            ),
            liveStatusText: "Live status",
            liveSummary: "Live summary",
            liveEvidence: ["live evidence"],
            liveConfidence: .high,
            liveRisks: ["live risk"]
        )

        #expect(task.displayStatusText == "Live status")
        #expect(task.displaySummary == "Live summary")
        #expect(task.displayEvidence == ["live evidence"])
        #expect(task.displayConfidence == .high)
        #expect(task.displayRisks == ["live risk"])

        let snapshot = AgentProcessSnapshot(
            activity: .delegation,
            currentFocus: "Current focus",
            leaderLiveStatus: "Leader is thinking",
            tasks: [
                task,
                AgentTask(
                    id: "task_2",
                    owner: .workerB,
                    title: "Review",
                    goal: "Review",
                    expectedOutput: "Review",
                    contextSummary: "Review",
                    toolPolicy: .reasoningOnly,
                    status: .running
                ),
                AgentTask(
                    id: "task_3",
                    owner: .workerC,
                    title: "Blocked",
                    goal: "Blocked",
                    expectedOutput: "Blocked",
                    contextSummary: "Blocked",
                    toolPolicy: .enabled,
                    status: .failed
                )
            ],
            activeTaskIDs: ["task_2"],
            recentUpdates: ["Legacy update"]
        )

        #expect(snapshot.activeTasks.map(\.id) == ["task_2"])
        #expect(snapshot.recentUpdateItems.map(\.summary) == ["Legacy update"])
        #expect(snapshot.progressSummary == "1 running · 1 done · 1 blocked")
    }
}
