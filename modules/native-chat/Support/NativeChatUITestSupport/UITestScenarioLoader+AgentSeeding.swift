import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation

@MainActor
extension UITestScenarioLoader {
    static func makeAgentConversation(
        title: String,
        timeOffset: TimeInterval
    ) -> Conversation {
        let conversation = makeAgentSeedConversation(
            title: title,
            timeOffset: timeOffset,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )

        let userMessage = Message(
            role: .user,
            content: "What is the safest rollout plan?"
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "Use an additive rollout with rollback gates and parity checks.",
            agentTrace: makeSeededAgentTrace()
        )

        conversation.messages = [userMessage, assistantMessage]
        userMessage.conversation = conversation
        assistantMessage.conversation = conversation
        return conversation
    }

    static func makeRunningAgentConversation(
        title: String,
        timeOffset: TimeInterval
    ) -> Conversation {
        let conversation = makeAgentSeedConversation(
            title: title,
            timeOffset: timeOffset,
            backgroundModeEnabled: true,
            serviceTier: .flex
        )

        let userMessage = Message(
            role: .user,
            content: "What should we validate before launch?"
        )
        let draftMessage = Message(
            role: .assistant,
            content: "",
            conversation: conversation,
            isComplete: false
        )

        conversation.messages = [userMessage, draftMessage]
        userMessage.conversation = conversation
        draftMessage.conversation = conversation
        conversation.agentConversationState = AgentConversationState(
            currentStage: .workersRoundOne,
            configuration: AgentConversationConfiguration(
                backgroundModeEnabled: true,
                serviceTier: .flex
            ),
            activeRun: makeRunningAgentSnapshot(
                draftMessageID: draftMessage.id,
                userMessageID: userMessage.id
            )
        )
        return conversation
    }

    static func makeRunningAgentSnapshot(
        draftMessageID: UUID,
        userMessageID: UUID
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            currentStage: .workersRoundOne,
            phase: .workerWave,
            draftMessageID: draftMessageID,
            latestUserMessageID: userMessageID,
            runConfiguration: AgentConversationConfiguration(
                backgroundModeEnabled: true,
                serviceTier: .flex
            ),
            leaderBriefSummary: "Prefer the safest release path with explicit validation gates.",
            processSnapshot: makeRunningAgentProcessSnapshot(),
            workersRoundOneSummaries: [
                AgentWorkerSummary(role: .workerA, summary: "Ship additively."),
                AgentWorkerSummary(role: .workerB, summary: "Call out rollback points."),
                AgentWorkerSummary(role: .workerC, summary: "Check monitoring gaps.")
            ],
            workersRoundOneProgress: [
                AgentWorkerProgress(role: .workerA, status: .completed),
                AgentWorkerProgress(role: .workerB, status: .running),
                AgentWorkerProgress(role: .workerC, status: .waiting)
            ],
            currentStreamingText: "",
            currentThinkingText: ""
        )
    }
}

private extension UITestScenarioLoader {
    static func makeAgentSeedConversation(
        title: String,
        timeOffset: TimeInterval,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier
    ) -> Conversation {
        let createdAt = Date(timeIntervalSinceNow: timeOffset)
        let updatedAt = Date(timeIntervalSinceNow: timeOffset)
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTierRawValue: serviceTier.rawValue,
            agentStateData: nil
        )
        conversation.mode = .agent
        return conversation
    }

    static func makeSeededAgentTrace() -> AgentTurnTrace {
        AgentTurnTrace(
            leaderBriefSummary: "Prefer the lowest-risk rollout path.",
            workerSummaries: [
                AgentWorkerSummary(
                    role: .workerA,
                    summary: "Ship additively and gate by parity.",
                    adoptedPoints: ["Keep rollback explicit."]
                )
            ],
            processSnapshot: AgentProcessSnapshot(
                activity: .completed,
                currentFocus: "Leader completed the rollout recommendation.",
                leaderAcceptedFocus: "Leader completed the rollout recommendation.",
                leaderLiveStatus: "Completed",
                leaderLiveSummary: "The rollout recommendation is grounded in accepted worker findings.",
                plan: [
                    AgentPlanStep(
                        id: "step_root",
                        owner: .leader,
                        status: .completed,
                        title: "Frame rollout answer",
                        summary: "Choose the safest rollout shape."
                    )
                ],
                tasks: [
                    AgentTask(
                        id: "task_validate_rollout",
                        owner: .workerA,
                        parentStepID: "step_root",
                        title: "Validate rollout shape",
                        goal: "Confirm the safest rollout path",
                        expectedOutput: "Concise rollout recommendation",
                        contextSummary: "Focus on additive rollout and rollback gates.",
                        toolPolicy: .enabled,
                        status: .completed,
                        resultSummary: "Ship additively and gate by parity."
                    )
                ],
                decisions: [
                    AgentDecision(
                        kind: .triage,
                        title: "Delegate",
                        summary: "Validate the rollout path before answering."
                    ),
                    AgentDecision(
                        kind: .finish,
                        title: "Finish",
                        summary: "The current evidence is sufficient for the final answer."
                    )
                ],
                events: [
                    AgentEvent(kind: .started, summary: "Started Agent run"),
                    AgentEvent(kind: .synthesisStarted, summary: "Leader began final synthesis")
                ],
                evidence: ["Rollback stayed explicit across the plan."],
                recentUpdates: [
                    "Worker A validated additive rollout with rollback gates.",
                    "Leader adopted explicit parity checks."
                ],
                stopReason: .sufficientAnswer,
                outcome: "Completed"
            ),
            completedStage: .finalSynthesis,
            outcome: "Completed"
        )
    }

    static func makeRunningAgentProcessSnapshot() -> AgentProcessSnapshot {
        AgentProcessSnapshot(
            activity: .delegation,
            currentFocus: "Leader delegated a bounded validation wave before synthesis.",
            leaderAcceptedFocus: "Leader delegated a bounded validation wave before synthesis.",
            leaderLiveStatus: "Reviewing worker results",
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
            recentUpdates: [
                "Leader split the work into answer, risk, and completeness tracks.",
                "Worker A completed the strongest answer path.",
                "Worker B is checking rollback wording."
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
}
