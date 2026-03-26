import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func performLeaderPlanning(
        _ phase: AgentPlanningEngine.PlanningPhase,
        decisionKind: AgentDecisionKind,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentLeaderPlanningResult {
        let planning = try await runLeaderPlanningPhase(
            phase,
            prepared: prepared,
            execution: execution,
            baseInput: baseInput
        )
        updateRoleResponseID(planning.responseID, for: .leader, in: prepared.conversation)
        applyLeaderDirective(
            planning.directive,
            decisionKind: decisionKind,
            to: execution,
            in: prepared.conversation,
            appendTasks: false
        )
        return planning
    }

    func repairCandidateDirective(
        from directive: AgentTaggedOutputParser.LeaderDirective,
        phase: LoopStep,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentTaggedOutputParser.LeaderDirective {
        if case .localPass = phase {
            return directive
        }

        return try await performLeaderLocalPass(
            prepared: prepared,
            execution: execution,
            baseInput: baseInput
        ).directive
    }

    func shouldSynthesizeDelegation(
        candidate: AgentTaggedOutputParser.LeaderDirective,
        shouldPushDelegation: Bool,
        synthesizedTasks: [AgentTask]
    ) -> Bool {
        (candidate.decision == .delegate || shouldPushDelegation) && !synthesizedTasks.isEmpty
    }

    func delegatedRepairDirective(
        candidate: AgentTaggedOutputParser.LeaderDirective,
        directive: AgentTaggedOutputParser.LeaderDirective,
        synthesizedTasks: [AgentTask]
    ) -> AgentTaggedOutputParser.LeaderDirective {
        AgentTaggedOutputParser.LeaderDirective(
            focus: candidate.focus.isEmpty ? directive.focus : candidate.focus,
            decision: .delegate,
            plan: candidate.plan.isEmpty ? directive.plan : candidate.plan,
            tasks: synthesizedTasks,
            decisionNote: candidate.decisionNote.isEmpty
                ? "Delegate a bounded worker wave before answering."
                : candidate.decisionNote,
            stopReason: nil
        )
    }

    func finalizeTaskResult(
        _ result: AgentWorkerExecutionResult,
        taskID: String,
        execution: AgentExecutionState,
        conversation: Conversation,
        completedTasks: inout [AgentTask]
    ) throws {
        if let role = result.task.owner.role {
            updateRoleResponseID(result.responseID, for: role, in: conversation)
        }
        AgentProcessProjector.recordTaskResult(
            result.task.result ?? AgentTaskResult(summary: result.task.title),
            for: taskID,
            status: .completed,
            on: &execution.snapshot
        )
        markPlanStepCompleted(for: result.task, on: &execution.snapshot)
        completedTasks.append(updatedTask(for: taskID, in: execution.snapshot) ?? result.task)
        persistSnapshot(execution, in: conversation)
    }
}
