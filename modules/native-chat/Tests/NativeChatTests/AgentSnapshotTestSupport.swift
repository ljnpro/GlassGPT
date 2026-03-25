import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import OpenAITransport
import SwiftData
@testable import NativeChatComposition

@MainActor
func makeSnapshotAgentScreenStore(hasAPIKey: Bool = false) throws -> AgentController {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)
    settingsValueStore.set(true, forKey: SettingsStore.Keys.hapticEnabled)

    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = hasAPIKey ? "sk-snapshot" : nil

    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let configurationProvider = RuntimeTestOpenAIConfigurationProvider()
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let responseParser = OpenAIResponseParser()
    let transport = StubOpenAITransport()
    let service = OpenAIService(
        requestBuilder: requestBuilder,
        responseParser: responseParser,
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
        transport: transport
    )

    return AgentController(
        modelContext: context,
        settingsStore: settingsStore,
        apiKeyStore: apiKeyStore,
        requestBuilder: requestBuilder,
        responseParser: responseParser,
        transport: transport,
        serviceFactory: { service }
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

@MainActor
func makeRunningAgentConversationSamples(in viewModel: AgentController) -> Conversation {
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
        content: "What changes should we make before launch?"
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

    viewModel.currentConversation = conversation
    viewModel.messages = [userMessage, draftMessage]
    viewModel.draftMessage = draftMessage
    viewModel.isRunning = true
    viewModel.isStreaming = true
    viewModel.isThinking = true
    viewModel.currentStage = .crossReview
    viewModel.currentThinkingText = "Comparing the first worker round and resolving disagreements."
    viewModel.currentStreamingText = "Finalizing the safest release recommendation."
    viewModel.workerProgress = [
        AgentWorkerProgress(role: .workerA, status: .completed),
        AgentWorkerProgress(role: .workerB, status: .running),
        AgentWorkerProgress(role: .workerC, status: .completed)
    ]
    viewModel.activeToolCalls = [
        ToolCallInfo(
            id: "agent_web",
            type: .webSearch,
            status: .searching,
            queries: ["zero-diff rollout checklist"]
        )
    ]

    return conversation
}
