import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func executeDynamicLoop(
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> AgentTaggedOutputParser.LeaderDirective {
        let maxWaves = 4
        var waveCount = 0
        var completedTasksForReview = currentCompletedTasks(from: execution.snapshot)
        var nextStep = initialLoopStep(for: execution.snapshot)
        var finalDirective: AgentTaggedOutputParser.LeaderDirective?

        while finalDirective == nil {
            try Task.checkCancellation()

            switch nextStep {
            case .triage:
                let planning = try await performLeaderTriage(
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput
                )
                let outcome = evaluateDirectiveOutcome(
                    planning.directive,
                    currentFocus: execution.snapshot.processSnapshot.currentFocus,
                    waveCount: &waveCount,
                    maxWaves: maxWaves
                )
                nextStep = outcome.nextStep
                finalDirective = outcome.finalDirective

            case let .delegate(tasks, decisionSummary):
                guard !tasks.isEmpty else {
                    nextStep = .review
                    continue
                }

                completedTasksForReview = try await runDelegationWave(
                    tasks: tasks,
                    decisionSummary: decisionSummary,
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput
                )
                nextStep = .review

            case .review:
                let planning = try await performLeaderReview(
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput,
                    completedTasks: completedTasksForReview
                )
                let outcome = evaluateDirectiveOutcome(
                    planning.directive,
                    currentFocus: execution.snapshot.processSnapshot.currentFocus,
                    waveCount: &waveCount,
                    maxWaves: maxWaves
                )
                nextStep = outcome.nextStep
                finalDirective = outcome.finalDirective
            }
        }

        return finalDirective ?? AgentTaggedOutputParser.LeaderDirective(
            focus: execution.snapshot.processSnapshot.currentFocus,
            decision: .finish,
            plan: execution.snapshot.processSnapshot.plan,
            tasks: [],
            decisionNote: "Leader decided the answer is sufficient.",
            stopReason: "Answer completed."
        )
    }

    func runDelegationWave(
        tasks: [AgentTask],
        decisionSummary: String,
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> [AgentTask] {
        AgentProcessProjector.updateFocus(
            execution.snapshot.processSnapshot.currentFocus.isEmpty
                ? "Delegating bounded work to workers."
                : execution.snapshot.processSnapshot.currentFocus,
            activity: .delegation,
            on: &execution.snapshot
        )
        persistSnapshot(execution, in: prepared.conversation)

        var handles: [(task: AgentTask, handle: Task<AgentWorkerExecutionResult, Error>)] = []
        for task in tasks.prefix(3) {
            AgentProcessProjector.markTaskRunning(task.id, on: &execution.snapshot)
            persistSnapshot(execution, in: prepared.conversation)
            handles.append(
                (
                    task: task,
                    handle: Task { @MainActor in
                        try await self.state.workerRuntime.runTask(
                            task,
                            apiKey: prepared.apiKey,
                            configuration: prepared.configuration,
                            conversation: prepared.conversation,
                            execution: execution,
                            baseInput: baseInput,
                            currentFocus: execution.snapshot.processSnapshot.currentFocus,
                            decisionSummary: decisionSummary
                        )
                    }
                )
            )
        }
        defer { handles.forEach { $0.handle.cancel() } }

        return try await collectDelegationResults(
            handles,
            execution: execution,
            conversation: prepared.conversation
        )
    }
}

private extension AgentRunCoordinator {
    struct DirectiveLoopOutcome {
        let nextStep: LoopStep
        let finalDirective: AgentTaggedOutputParser.LeaderDirective?
    }

    func initialLoopStep(for snapshot: AgentRunSnapshot) -> LoopStep {
        let queuedTasks = currentQueuedTasks(from: snapshot)
        if queuedTasks.isEmpty {
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
        AgentProcessProjector.updateFocus(
            "Leader is classifying the request and setting the plan.",
            activity: .triage,
            on: &execution.snapshot
        )
        persistSnapshot(execution, in: prepared.conversation)

        let planning = try await state.planningEngine.runTriage(
            apiKey: prepared.apiKey,
            configuration: prepared.configuration,
            conversation: prepared.conversation,
            baseInput: baseInput
        )
        updateRoleResponseID(planning.responseID, for: .leader, in: prepared.conversation)
        applyLeaderDirective(
            planning.directive,
            decisionKind: .triage,
            to: execution,
            in: prepared.conversation,
            appendTasks: planning.directive.decision == .delegate
        )
        return planning
    }

    func performLeaderReview(
        prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        completedTasks: [AgentTask]
    ) async throws -> AgentLeaderPlanningResult {
        AgentProcessProjector.updateFocus(
            "Leader is reviewing worker results and deciding whether another wave is needed.",
            activity: .reviewing,
            on: &execution.snapshot
        )
        persistSnapshot(execution, in: prepared.conversation)

        let planning = try await state.planningEngine.runReview(
            apiKey: prepared.apiKey,
            configuration: prepared.configuration,
            conversation: prepared.conversation,
            baseInput: baseInput,
            snapshot: execution.snapshot.processSnapshot,
            completedTasks: completedTasks
        )
        updateRoleResponseID(planning.responseID, for: .leader, in: prepared.conversation)
        applyLeaderDirective(
            planning.directive,
            decisionKind: .revise,
            to: execution,
            in: prepared.conversation,
            appendTasks: planning.directive.decision == .delegate
        )
        return planning
    }

    func evaluateDirectiveOutcome(
        _ directive: AgentTaggedOutputParser.LeaderDirective,
        currentFocus: String,
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
                finalDirective: forceBudgetStopDirective(from: directive, focus: currentFocus)
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

    func collectDelegationResults(
        _ handles: [(task: AgentTask, handle: Task<AgentWorkerExecutionResult, Error>)],
        execution: AgentExecutionState,
        conversation: Conversation
    ) async throws -> [AgentTask] {
        var completedTasks: [AgentTask] = []
        for entry in handles {
            do {
                let result = try await entry.handle.value
                if let role = result.task.owner.role {
                    updateRoleResponseID(result.responseID, for: role, in: conversation)
                }
                AgentProcessProjector.recordTaskResult(
                    result.task.result ?? AgentTaskResult(summary: result.task.title),
                    for: result.task.id,
                    status: .completed,
                    on: &execution.snapshot
                )
                markPlanStepCompleted(for: result.task, on: &execution.snapshot)
                completedTasks.append(updatedTask(for: result.task.id, in: execution.snapshot) ?? result.task)
                persistSnapshot(execution, in: conversation)
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

enum LoopStep {
    case triage
    case delegate(tasks: [AgentTask], decisionSummary: String)
    case review
}
