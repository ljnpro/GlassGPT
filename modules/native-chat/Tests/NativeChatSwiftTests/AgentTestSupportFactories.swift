import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport
@testable import NativeChatComposition

@MainActor
func makeSnapshotAgentScreenStore(hasAPIKey: Bool = false) throws -> AgentController {
    try makeTestAgentController(
        apiKey: hasAPIKey ? "sk-snapshot" : "",
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
        hapticsEnabled: true
    )
}

@MainActor
func makeCompletedAgentConversationSamples(in viewModel: AgentController) -> Conversation {
    let conversation = Conversation(
        title: "Agent Review",
        modeRawValue: ConversationMode.agent.rawValue,
        model: ModelType.gpt5_4.rawValue,
        reasoningEffort: ReasoningEffort.high.rawValue,
        backgroundModeEnabled: false,
        serviceTierRawValue: ServiceTier.standard.rawValue
    )
    conversation.mode = .agent

    let userMessage = Message(
        role: .user,
        content: "What is the safest rollout plan?"
    )
    let assistantMessage = Message(
        role: .assistant,
        content: "Ship additively with parity checks and a rollback gate at every milestone.",
        agentTrace: makeCompletedAgentTrace()
    )
    conversation.messages = [userMessage, assistantMessage]
    userMessage.conversation = conversation
    assistantMessage.conversation = conversation
    viewModel.currentConversation = conversation
    viewModel.messages = [userMessage, assistantMessage]
    return conversation
}

private func makeCompletedAgentTrace() -> AgentTurnTrace {
    AgentTurnTrace(
        leaderBriefSummary: "Prefer the lowest-risk rollout path.",
        workerSummaries: [
            AgentWorkerSummary(
                role: .workerA,
                summary: "Use an additive rollout with rollback gates.",
                adoptedPoints: ["Keep parity checks visible."]
            ),
            AgentWorkerSummary(
                role: .workerB,
                summary: "Do not mutate existing data flows in place.",
                adoptedPoints: ["Call out failure domains."]
            ),
            AgentWorkerSummary(
                role: .workerC,
                summary: "Document missing monitoring and launch sequencing.",
                adoptedPoints: ["Add validation checkpoints."]
            )
        ],
        processSnapshot: makeCompletedAgentProcessSnapshot(),
        completedStage: .finalSynthesis,
        outcome: "Completed"
    )
}

private func makeCompletedAgentProcessSnapshot() -> AgentProcessSnapshot {
    AgentProcessSnapshot(
        activity: .completed,
        currentFocus: "Leader completed the rollout recommendation.",
        leaderAcceptedFocus: "Leader completed the rollout recommendation.",
        leaderLiveStatus: "Completed",
        leaderLiveSummary: "The rollout recommendation is grounded in the accepted worker findings.",
        plan: [
            AgentPlanStep(
                id: "step_root",
                owner: .leader,
                status: .completed,
                title: "Frame rollout plan",
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
                resultSummary: "Use additive rollout with rollback gates."
            )
        ],
        decisions: [
            AgentDecision(
                kind: .triage,
                title: "Delegate",
                summary: "Validate the rollout recommendation before answering."
            ),
            AgentDecision(
                kind: .finish,
                title: "Finish",
                summary: "The answer is strong enough to deliver."
            )
        ],
        events: [
            AgentEvent(kind: .started, summary: "Started Agent run"),
            AgentEvent(kind: .synthesisStarted, summary: "Leader began final synthesis")
        ],
        evidence: ["Rollback gates remained explicit."],
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
    )
}
