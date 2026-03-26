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

    static func makeCompletedVisibleSynthesisAgentConversation(
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
            thinking: "Checking supporting evidence before the final answer.",
            conversation: conversation,
            isComplete: false
        )
        draftMessage.toolCalls = [
            ToolCallInfo(
                id: "agent_visible_search",
                type: .webSearch,
                status: .searching,
                queries: ["launch checklist"]
            )
        ]

        conversation.messages = [userMessage, draftMessage]
        userMessage.conversation = conversation
        draftMessage.conversation = conversation
        conversation.agentConversationState = AgentConversationState(
            currentStage: .finalSynthesis,
            configuration: AgentConversationConfiguration(
                backgroundModeEnabled: true,
                serviceTier: .flex
            ),
            activeRun: makeCompletedVisibleSynthesisSnapshot(
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
                recentUpdateItems: [
                    AgentProcessUpdate(
                        kind: .councilCompleted,
                        source: .leader,
                        phase: .completed,
                        summary: "Council completed"
                    ),
                    AgentProcessUpdate(
                        kind: .workerCompleted,
                        source: .workerA,
                        phase: .workerWave,
                        taskID: "task_validate_rollout",
                        summary: "Worker A completed."
                    ),
                    AgentProcessUpdate(
                        kind: .planUpdated,
                        source: .leader,
                        phase: .leaderReview,
                        summary: "Updated plan"
                    )
                ],
                stopReason: .sufficientAnswer,
                outcome: "Completed"
            ),
            completedStage: .finalSynthesis,
            outcome: "Completed"
        )
    }
}
