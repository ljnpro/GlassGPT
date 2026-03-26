import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

struct DirectiveLoopOutcome {
    let nextStep: LoopStep
    let finalDirective: AgentTaggedOutputParser.LeaderDirective?
}

enum LoopStep {
    case triage
    case localPass
    case delegate(tasks: [AgentTask], decisionSummary: String)
    case review
}

extension AgentRunCoordinator {
    func initialLoopStep(for snapshot: AgentRunSnapshot) -> LoopStep {
        let queuedTasks = currentQueuedTasks(from: snapshot)
        if queuedTasks.isEmpty {
            if snapshot.phase == .leaderLocalPass {
                return .localPass
            }
            if snapshot.currentStage == .crossReview || snapshot.processSnapshot.activity == .reviewing {
                return .review
            }
            return .triage
        }
        return .delegate(
            tasks: queuedTasks,
            decisionSummary: latestDecisionSummary(in: snapshot)
        )
    }

    func performLeaderTriage(
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentLeaderPlanningResult {
        try await performLeaderPlanning(
            AgentPlanningEngine.PlanningPhase.triage,
            decisionKind: AgentDecisionKind.triage,
            prepared: prepared,
            execution: execution,
            baseInput: baseInput
        )
    }

    func performLeaderLocalPass(
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentLeaderPlanningResult {
        try await performLeaderPlanning(
            AgentPlanningEngine.PlanningPhase.localPass,
            decisionKind: AgentDecisionKind.localPass,
            prepared: prepared,
            execution: execution,
            baseInput: baseInput
        )
    }

    func performLeaderReview(
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        completedTasks: [AgentTask]
    ) async throws -> AgentLeaderPlanningResult {
        try await performLeaderPlanning(
            AgentPlanningEngine.PlanningPhase.review(
                snapshot: execution.snapshot.processSnapshot,
                completedTasks: completedTasks
            ),
            decisionKind: AgentDecisionKind.revise,
            prepared: prepared,
            execution: execution,
            baseInput: baseInput
        )
    }

    func collectDelegationResults(
        _ handles: [(task: AgentTask, handle: Task<AgentWorkerExecutionResult, Error>)],
        execution: AgentExecutionState,
        conversation: Conversation
    ) async throws -> [AgentTask] {
        var completedTasks: [AgentTask] = []
        for entry in handles {
            do {
                let result = try await entry.handle.value
                try finalizeTaskResult(
                    result,
                    taskID: entry.task.id,
                    execution: execution,
                    conversation: conversation,
                    completedTasks: &completedTasks
                )
            } catch {
                AgentProcessProjector.recordTaskResult(
                    AgentTaskResult(summary: "Worker task failed."),
                    for: entry.task.id,
                    status: .failed,
                    on: &execution.snapshot
                )
                persistSnapshot(execution, in: conversation)
                throw error
            }
        }
        return completedTasks
    }
}
