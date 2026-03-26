import ChatDomain
import Foundation
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentProcessProjectionTests {
    @Test func `leader planning milestone copy stays distinct from the live bootstrap summary`() {
        #expect(
            AgentPlanningEngine.PlanningPhase.triage.milestoneSummary
                != AgentPlanningEngine.PlanningPhase.triage.bootstrapSummary
        )
        #expect(
            AgentPlanningEngine.PlanningPhase.localPass.milestoneSummary
                != AgentPlanningEngine.PlanningPhase.localPass.bootstrapSummary
        )
        #expect(AgentPlanningEngine.PlanningPhase.review(
            snapshot: AgentProcessSnapshot(),
            completedTasks: []
        ).milestoneSummary != AgentPlanningEngine.PlanningPhase.review(
            snapshot: AgentProcessSnapshot(),
            completedTasks: []
        ).bootstrapSummary)
    }

    @Test func `leader live preview deltas do not append recent updates`() {
        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        AgentRecentUpdateProjector.recordLeaderPhaseMilestone(
            "Scoping the request.",
            phase: .leaderTriage,
            on: &snapshot
        )
        let milestoneCount = snapshot.processSnapshot.recentUpdateItems.count

        AgentProcessProjector.updateLeaderLivePreview(
            status: "Scoping the request",
            summary: "Exploring the user ask from one angle.",
            on: &snapshot
        )
        AgentProcessProjector.updateLeaderLivePreview(
            status: "Scoping the request",
            summary: "Exploring the user ask from a second angle.",
            on: &snapshot
        )

        #expect(snapshot.processSnapshot.recentUpdateItems.count == milestoneCount)
        #expect(snapshot.processSnapshot.recentUpdateItems.contains(where: {
            $0.kind == .leaderPhase && $0.summary == "Scoping the request."
        }))
    }

    @Test func `worker live preview deltas stay in worker cards and out of recent updates`() {
        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        let task = AgentTask(
            id: "task_worker_b",
            owner: .workerB,
            title: "Stress launch risks",
            goal: "Find the riskiest edge cases",
            expectedOutput: "Short risk summary",
            contextSummary: "Focus on rollback and monitoring gaps.",
            toolPolicy: .enabled,
            status: .queued
        )

        AgentProcessProjector.queueTasks([task], on: &snapshot)
        AgentProcessProjector.markTaskRunning(task.id, on: &snapshot)
        let milestoneCount = snapshot.processSnapshot.recentUpdateItems.count

        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: "Checking rollback",
            summary: "The launch draft still needs one explicit rollback gate.",
            evidence: ["Rollback gate is still implicit."],
            confidence: .medium,
            risks: ["Recovery steps are underspecified."],
            on: &snapshot
        )
        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: "Checking rollback",
            summary: "The launch draft still needs rollback wording and one monitoring checkpoint.",
            evidence: ["Rollback gate is still implicit."],
            confidence: .medium,
            risks: ["Recovery steps are underspecified."],
            on: &snapshot
        )

        #expect(snapshot.processSnapshot.recentUpdateItems.count == milestoneCount)
        let liveTask = snapshot.processSnapshot.tasks.first(where: { $0.id == task.id })
        #expect(liveTask?.liveSummary == "The launch draft still needs rollback wording and one monitoring checkpoint.")
    }

    @Test func `recent updates coalesce recovery rows and keep only the newest five milestones`() {
        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )

        AgentRecentUpdateProjector.recordLeaderPhaseMilestone(
            "Scoping the request.",
            phase: .leaderTriage,
            on: &snapshot
        )
        AgentRecentUpdateProjector.recordPlanMilestone(
            "Updated plan",
            phase: .leaderTriage,
            on: &snapshot
        )
        AgentRecentUpdateProjector.recordWorkerWaveQueued(count: 3, on: &snapshot)
        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &snapshot)
        AgentProcessProjector.updateRecoveryState(.replayingCheckpoint, on: &snapshot)
        AgentRecentUpdateProjector.recordCouncilCompleted("Done", on: &snapshot)

        #expect(snapshot.processSnapshot.recentUpdateItems.count == 5)
        #expect(snapshot.processSnapshot.recentUpdateItems.first?.kind == .councilCompleted)
        #expect(snapshot.processSnapshot.recentUpdateItems.contains(where: {
            $0.kind == .recovery && $0.summary == AgentRecoveryState.replayingCheckpoint.displayName
        }))
        #expect(snapshot.processSnapshot.recentUpdateItems.count(where: { $0.kind == .recovery }) == 1)
        #expect(snapshot.processSnapshot.recentUpdateItems.count(where: {
            $0.kind == .leaderPhase && $0.phase == .leaderTriage
        }) == 1)
    }

    @Test func `recent updates collapse repeated startup leader milestones and repeated worker milestones`() {
        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        let workerTask = AgentTask(
            id: "task_worker_b_repeat",
            owner: .workerB,
            title: "Check launch risk",
            goal: "Find the main launch risk",
            expectedOutput: "Short risk summary",
            contextSummary: "Focus on rollback gaps.",
            toolPolicy: .enabled,
            status: .running
        )

        for summary in [
            "Classifying the request and shaping the first plan.",
            "Classifying the request and shaping the first plan",
            "Classifying the request and shaping the first plan.",
            "Classifying the request and shaping the first plan.."
        ] {
            AgentRecentUpdateProjector.recordLeaderPhaseMilestone(
                summary,
                phase: .leaderTriage,
                on: &snapshot
            )
        }
        AgentRecentUpdateProjector.recordWorkerMilestone(
            kind: .workerStarted,
            task: workerTask,
            summary: "Worker B started.",
            on: &snapshot
        )
        AgentRecentUpdateProjector.recordWorkerMilestone(
            kind: .workerStarted,
            task: workerTask,
            summary: "Worker B started.",
            on: &snapshot
        )
        AgentRecentUpdateProjector.recordWorkerMilestone(
            kind: .workerCompleted,
            task: workerTask,
            summary: "Worker B completed.",
            on: &snapshot
        )

        #expect(snapshot.processSnapshot.recentUpdateItems.count(where: { $0.kind == .leaderPhase }) == 1)
        #expect(snapshot.processSnapshot.recentUpdateItems.count(where: {
            $0.kind == .workerStarted || $0.kind == .workerCompleted
        }) == 1)
        #expect(snapshot.processSnapshot.recentUpdateItems.contains(where: {
            $0.kind == .workerCompleted && $0.summary == "Worker B completed."
        }))
    }

    @Test func `legacy recent update spam is rebuilt into semantic milestones`() {
        let workerTask = AgentTask(
            id: "task_worker_b_legacy",
            owner: .workerB,
            title: "Check launch risk",
            goal: "Find the main launch risk",
            expectedOutput: "Short risk summary",
            contextSummary: "Focus on rollback gaps.",
            toolPolicy: .enabled,
            status: .completed,
            result: AgentTaskResult(
                summary: "The launch still needs one rollback gate.",
                evidence: ["Rollback wording is still implicit."]
            ),
            completedAt: .now
        )
        var snapshot = AgentRunSnapshot(
            currentStage: .crossReview,
            phase: .leaderReview,
            draftMessageID: UUID(),
            latestUserMessageID: UUID(),
            processSnapshot: AgentProcessSnapshot(
                activity: .reviewing,
                currentFocus: "Leader is reviewing persisted worker findings.",
                leaderAcceptedFocus: "Leader is reviewing persisted worker findings.",
                leaderLiveStatus: "Reviewing worker results",
                leaderLiveSummary: "Reviewing persisted worker findings before the final answer.",
                tasks: [workerTask],
                recentUpdates: [
                    "Worker B: rollback wording is still implicit.",
                    "Worker B: rollback wording is still implicit..",
                    "Worker B: rollback wording is still implicit and still incomplete."
                ]
            )
        )

        AgentRecentUpdateProjector.sanitizeRecentUpdates(on: &snapshot)

        #expect(snapshot.processSnapshot.recentUpdateItems.isEmpty == false)
        #expect(snapshot.processSnapshot.recentUpdateItems.allSatisfy {
            $0.kind != AgentProcessUpdateKind.legacy
        })
        #expect(snapshot.processSnapshot.recentUpdateItems.count(where: {
            $0.kind == AgentProcessUpdateKind.workerCompleted
        }) == 1)
        #expect(snapshot.processSnapshot.recentUpdateItems.count(where: {
            $0.kind == AgentProcessUpdateKind.leaderPhase
        }) == 1)
        #expect(snapshot.processSnapshot.recentUpdateItems.count <= 5)
    }
}
