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
                let directive = try await repairedDirectiveIfNeeded(
                    planning.directive,
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput,
                    completedTasks: completedTasksForReview,
                    phase: .triage
                )
                let outcome = evaluateDirectiveOutcome(
                    directive,
                    prepared: prepared,
                    waveCount: &waveCount,
                    maxWaves: maxWaves
                )
                nextStep = outcome.nextStep
                finalDirective = outcome.finalDirective

            case .localPass:
                let planning = try await performLeaderLocalPass(
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput
                )
                let directive = try await repairedDirectiveIfNeeded(
                    planning.directive,
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput,
                    completedTasks: completedTasksForReview,
                    phase: .localPass
                )
                let outcome = evaluateDirectiveOutcome(
                    directive,
                    prepared: prepared,
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
                let directive = try await repairedDirectiveIfNeeded(
                    planning.directive,
                    prepared: prepared,
                    execution: execution,
                    baseInput: baseInput,
                    completedTasks: completedTasksForReview,
                    phase: .review
                )
                let outcome = evaluateDirectiveOutcome(
                    directive,
                    prepared: prepared,
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
        let runConfiguration = frozenRunConfiguration(for: execution, conversation: prepared.conversation)
        AgentProcessProjector.updateFocus(
            execution.snapshot.processSnapshot.currentFocus.isEmpty
                ? "Delegating bounded work to workers."
                : execution.snapshot.processSnapshot.currentFocus,
            activity: .delegation,
            on: &execution.snapshot
        )
        let missingTasks = tasks.filter { task in
            !execution.snapshot.processSnapshot.tasks.contains(where: { $0.id == task.id })
        }
        if !missingTasks.isEmpty {
            AgentProcessProjector.queueTasks(missingTasks, on: &execution.snapshot)
        }
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
                            configuration: runConfiguration,
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
