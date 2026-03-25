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
        agentTrace: AgentTurnTrace(
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
            completedStage: .finalSynthesis,
            outcome: "Completed"
        )
    )
    conversation.messages = [userMessage, assistantMessage]
    userMessage.conversation = conversation
    assistantMessage.conversation = conversation
    viewModel.currentConversation = conversation
    viewModel.messages = [userMessage, assistantMessage]
    return conversation
}
