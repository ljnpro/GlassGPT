import ChatDomain
import Foundation

extension UITestScenarioLoader {
    static func makeCompletedVisibleSynthesisSnapshot(
        draftMessageID: UUID,
        userMessageID: UUID
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            currentStage: .finalSynthesis,
            phase: .finalSynthesis,
            draftMessageID: draftMessageID,
            latestUserMessageID: userMessageID,
            runConfiguration: AgentConversationConfiguration(
                backgroundModeEnabled: true,
                serviceTier: .flex
            ),
            leaderBriefSummary: "Prefer the safest release path with explicit validation gates.",
            processSnapshot: AgentProcessSnapshot(
                activity: .completed,
                currentFocus: "Leader completed the internal Agent council.",
                leaderAcceptedFocus: "Leader completed the internal Agent council.",
                leaderLiveStatus: "Done",
                leaderLiveSummary: "",
                plan: [
                    AgentPlanStep(
                        id: "step_root",
                        owner: .leader,
                        status: .completed,
                        title: "Shape the launch answer",
                        summary: "Choose the strongest validated launch answer."
                    )
                ],
                tasks: runningAgentTasks().map(completeVisibleSynthesisTask),
                decisions: [
                    AgentDecision(
                        kind: .finish,
                        title: "Finish",
                        summary: "The internal council is done and the final answer can be written."
                    )
                ],
                events: [
                    AgentEvent(kind: .started, summary: "Started Agent run"),
                    AgentEvent(kind: .completed, summary: "Done")
                ],
                evidence: ["Rollback wording and monitoring checkpoints were accepted."],
                recentUpdateItems: [
                    AgentProcessUpdate(
                        kind: .councilCompleted,
                        source: .leader,
                        phase: .completed,
                        summary: "Done"
                    ),
                    AgentProcessUpdate(
                        kind: .workerCompleted,
                        source: .workerB,
                        phase: .workerWave,
                        taskID: "task_risks",
                        summary: "Worker B completed."
                    ),
                    AgentProcessUpdate(
                        kind: .workerCompleted,
                        source: .workerA,
                        phase: .workerWave,
                        taskID: "task_answer",
                        summary: "Worker A completed."
                    )
                ],
                stopReason: .sufficientAnswer,
                outcome: "Done"
            ),
            currentStreamingText: "",
            currentThinkingText: "Checking supporting evidence before the final answer.",
            visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                statusText: "Searching the web",
                summaryText: "Checking supporting evidence before the final answer.",
                recoveryState: .idle
            ),
            activeToolCalls: [
                ToolCallInfo(
                    id: "agent_visible_search",
                    type: .webSearch,
                    status: .searching,
                    queries: ["launch checklist"]
                )
            ],
            isStreaming: true,
            isThinking: false
        )
    }

    static func makeRunningAgentProcessSnapshot() -> AgentProcessSnapshot {
        AgentProcessSnapshot(
            activity: .delegation,
            currentFocus: "Leader delegated a bounded validation wave before synthesis.",
            leaderAcceptedFocus: "Leader delegated a bounded validation wave before synthesis.",
            leaderLiveStatus: "Leader review",
            leaderLiveSummary: "Comparing the strongest worker recommendation with the risk findings.",
            plan: [
                AgentPlanStep(
                    id: "step_root",
                    owner: .leader,
                    status: .running,
                    title: "Shape the launch answer",
                    summary: "Decide what to keep local and what to delegate."
                ),
                AgentPlanStep(
                    id: "step_risk",
                    parentStepID: "step_root",
                    owner: .workerB,
                    status: .running,
                    title: "Stress launch risks",
                    summary: "Surface rollback and monitoring gaps."
                )
            ],
            tasks: runningAgentTasks(),
            decisions: [
                AgentDecision(
                    kind: .triage,
                    title: "Delegate",
                    summary: "Run one bounded validation wave before synthesis."
                )
            ],
            events: [
                AgentEvent(kind: .started, summary: "Started Agent run"),
                AgentEvent(kind: .taskStarted, summary: "Worker B started stress-testing the launch plan")
            ],
            evidence: ["Worker A already converged on additive rollout."],
            activeTaskIDs: ["task_risks"],
            recentUpdateItems: [
                AgentProcessUpdate(
                    kind: .workerStarted,
                    source: .workerB,
                    phase: .workerWave,
                    taskID: "task_risks",
                    summary: "Worker B started Stress launch risks."
                ),
                AgentProcessUpdate(
                    kind: .workerCompleted,
                    source: .workerA,
                    phase: .workerWave,
                    taskID: "task_answer",
                    summary: "Worker A completed."
                ),
                AgentProcessUpdate(
                    kind: .workerWaveQueued,
                    source: .leader,
                    phase: .workerWave,
                    summary: "Queued 3 worker task(s)."
                ),
                AgentProcessUpdate(
                    kind: .leaderPhase,
                    source: .leader,
                    phase: .leaderReview,
                    summary: "Reviewing worker results."
                ),
                AgentProcessUpdate(
                    kind: .runStarted,
                    source: .system,
                    phase: .leaderTriage,
                    summary: "Started Agent run"
                )
            ],
            outcome: "In progress"
        )
    }

    static func runningAgentTasks() -> [AgentTask] {
        [
            AgentTask(
                id: "task_answer",
                owner: .workerA,
                parentStepID: "step_root",
                title: "Draft strongest answer",
                goal: "Return the best launch recommendation",
                expectedOutput: "Concise recommendation",
                contextSummary: "Focus on release confidence and ordering.",
                toolPolicy: .enabled,
                status: .completed,
                resultSummary: "Ship additively with parity checks."
            ),
            AgentTask(
                id: "task_risks",
                owner: .workerB,
                parentStepID: "step_risk",
                title: "Stress launch risks",
                goal: "Surface failure modes",
                expectedOutput: "Concise risk summary",
                contextSummary: "Look for rollback and monitoring gaps.",
                toolPolicy: .enabled,
                status: .running,
                liveStatusText: "Checking rollback",
                liveSummary: "The launch draft still needs an explicit rollback gate and one monitoring checkpoint.",
                liveEvidence: ["Rollback wording is still too implicit."],
                liveConfidence: .medium
            ),
            AgentTask(
                id: "task_completeness",
                owner: .workerC,
                parentStepID: "step_root",
                title: "Check completeness",
                goal: "Find missing launch gates",
                expectedOutput: "Short completeness notes",
                contextSummary: "Keep the answer structured and complete.",
                toolPolicy: .reasoningOnly,
                status: .queued
            )
        ]
    }

    static func completeVisibleSynthesisTask(_ task: AgentTask) -> AgentTask {
        var updatedTask = task
        switch updatedTask.id {
        case "task_risks":
            updatedTask.status = .completed
            updatedTask.liveStatusText = nil
            updatedTask.liveSummary = nil
            updatedTask.resultSummary = "Rollback gate wording and monitoring checkpoint added."
        case "task_completeness":
            updatedTask.status = .completed
            updatedTask.resultSummary = "No critical completeness gaps remain."
        default:
            break
        }
        return updatedTask
    }
}
