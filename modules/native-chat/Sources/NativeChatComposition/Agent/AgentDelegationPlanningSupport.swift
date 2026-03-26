import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func evaluateDirectiveOutcome(
        _ directive: AgentTaggedOutputParser.LeaderDirective,
        prepared: PreparedAgentTurn,
        waveCount: inout Int,
        maxWaves: Int
    ) -> DirectiveLoopOutcome {
        guard directive.decision == .delegate, !directive.tasks.isEmpty else {
            return DirectiveLoopOutcome(nextStep: .review, finalDirective: directive)
        }

        waveCount += 1
        if waveCount > maxWaves {
            return DirectiveLoopOutcome(
                nextStep: .review,
                finalDirective: forceBudgetStopDirective(
                    from: directive,
                    focus: executionFocusFallback(from: directive, prepared: prepared)
                )
            )
        }

        return DirectiveLoopOutcome(
            nextStep: .delegate(
                tasks: pendingTasksToRun(from: directive.tasks),
                decisionSummary: directive.decisionNote
            ),
            finalDirective: nil
        )
    }

    func repairedDirectiveIfNeeded(
        _ directive: AgentTaggedOutputParser.LeaderDirective,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        completedTasks: [AgentTask],
        phase: LoopStep
    ) async throws -> AgentTaggedOutputParser.LeaderDirective {
        if directive.decision == .delegate, !directive.tasks.isEmpty {
            return directive
        }

        let shouldPushDelegation = shouldPreferDelegation(for: prepared)
        let shouldRepair = directive.decision == .delegate ||
            (directive.decision == .finish && shouldPushDelegation && completedTasks.isEmpty)
        guard shouldRepair else {
            return directive
        }

        let candidate = try await repairCandidateDirective(
            from: directive,
            phase: phase,
            prepared: prepared,
            execution: execution,
            baseInput: baseInput
        )
        if candidate.decision == .delegate, !candidate.tasks.isEmpty {
            return candidate
        }

        let synthesizedTasks = synthesizeWorkerTasks(
            from: candidate.plan.isEmpty ? directive.plan : candidate.plan,
            focus: candidate.focus.isEmpty ? directive.focus : candidate.focus
        )
        if shouldSynthesizeDelegation(
            candidate: candidate,
            shouldPushDelegation: shouldPushDelegation,
            synthesizedTasks: synthesizedTasks
        ) {
            return delegatedRepairDirective(
                candidate: candidate,
                directive: directive,
                synthesizedTasks: synthesizedTasks
            )
        }

        guard directive.decision == .delegate else {
            return directive
        }

        return AgentTaggedOutputParser.LeaderDirective(
            focus: candidate.focus.isEmpty ? directive.focus : candidate.focus,
            decision: .finish,
            plan: candidate.plan.isEmpty ? directive.plan : candidate.plan,
            tasks: [],
            decisionNote: "Leader kept the answer local after the delegation repair produced no bounded tasks.",
            stopReason: "Answer completed."
        )
    }

    func shouldPreferDelegation(for prepared: PreparedAgentTurn) -> Bool {
        if !prepared.attachmentsToUpload.isEmpty {
            return true
        }

        let normalized = prepared.latestUserText.lowercased()
        if normalized.count > 80 || normalized.contains("\n") {
            return true
        }

        let delegationSignals = [
            "compare", "comparison", "research", "investigate", "analyze", "analysis",
            "plan", "design", "ship", "rollout", "implement", "code", "tradeoff",
            "trade-off", "risk", "options", "sources", "latest", "edge case"
        ]
        return delegationSignals.contains(where: { normalized.contains($0) })
    }

    func synthesizeWorkerTasks(
        from plan: [AgentPlanStep],
        focus: String
    ) -> [AgentTask] {
        let workerOwners: [AgentTaskOwner] = [.workerA, .workerB, .workerC]
        let candidateSteps = plan.filter { $0.owner != .leader }
        guard !candidateSteps.isEmpty else {
            return [
                AgentTask(
                    owner: .workerA,
                    title: "Research strongest answer",
                    goal: "Collect the strongest direct answer path for the current request.",
                    expectedOutput: "Return a concise recommended answer path.",
                    contextSummary: focus,
                    toolPolicy: .enabled
                )
            ]
        }

        return Array(candidateSteps.prefix(3).enumerated()).map { index, step in
            AgentTask(
                owner: workerOwners[index],
                parentStepID: step.id,
                title: step.title,
                goal: step.summary,
                expectedOutput: "Return a concise worker summary for this plan step.",
                contextSummary: focus,
                toolPolicy: index == 2 ? .reasoningOnly : .enabled
            )
        }
    }

    func executionFocusFallback(
        from directive: AgentTaggedOutputParser.LeaderDirective,
        prepared: PreparedAgentTurn
    ) -> String {
        let focus = directive.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        return focus.isEmpty ? prepared.latestUserText : focus
    }
}
