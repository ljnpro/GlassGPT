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
            processSnapshot: AgentProcessSnapshot(
                activity: .completed,
                currentFocus: "Leader completed the rollout recommendation.",
                plan: [
                    AgentPlanStep(
                        id: "step_root",
                        owner: .leader,
                        status: .completed,
                        title: "Frame rollout plan",
                        summary: "Choose the safest rollout shape."
                    ),
                    AgentPlanStep(
                        id: "step_validate",
                        parentStepID: "step_root",
                        owner: .workerA,
                        status: .completed,
                        title: "Validate rollout shape",
                        summary: "Confirm rollback, parity, and monitoring checkpoints."
                    )
                ],
                tasks: [
                    AgentTask(
                        owner: .workerA,
                        parentStepID: "step_validate",
                        title: "Validate rollout shape",
                        goal: "Confirm the safest rollout path",
                        expectedOutput: "Concise rollout recommendation",
                        contextSummary: "Focus on additive rollout and rollback gates.",
                        toolPolicy: .enabled,
                        status: .completed,
                        resultSummary: "Use additive rollout with rollback gates.",
                        result: AgentTaskResult(
                            summary: "Use additive rollout with rollback gates.",
                            evidence: ["Parity checks remain visible at every milestone."],
                            confidence: .high
                        )
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
                evidence: ["Rollback gates stayed explicit across the plan."],
                stopReason: .sufficientAnswer,
                outcome: "Completed"
            ),
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
    viewModel.currentStage = .workersRoundOne
    viewModel.leaderReasoningEffort = .high
    viewModel.workerReasoningEffort = .medium
    viewModel.backgroundModeEnabled = true
    viewModel.serviceTier = .flex
    viewModel.leaderBriefSummary = "Prefer a low-risk rollout with explicit failure-domain checks."
    viewModel.currentThinkingText = "Comparing the first worker round and resolving disagreements."
    viewModel.currentStreamingText = "Finalizing the safest release recommendation."
    viewModel.processSnapshot = makeRunningAgentProcessSnapshot()
    viewModel.activeToolCalls = [
        ToolCallInfo(
            id: "agent_web",
            type: .webSearch,
            status: .searching,
            queries: ["zero-diff rollout checklist"]
        )
    ]
    viewModel.workersRoundOneProgress = [
        AgentWorkerProgress(role: .workerA, status: .completed),
        AgentWorkerProgress(role: .workerB, status: .running),
        AgentWorkerProgress(role: .workerC, status: .waiting)
    ]

    return conversation
}

private func makeRunningAgentProcessSnapshot() -> AgentProcessSnapshot {
    AgentProcessSnapshot(
        activity: .delegation,
        currentFocus: "Leader delegated a bounded validation wave before writing the answer.",
        plan: [
            AgentPlanStep(
                id: "step_root",
                owner: .leader,
                status: .running,
                title: "Shape the launch answer",
                summary: "Choose which work stays local and which goes to workers."
            ),
            AgentPlanStep(
                id: "step_checks",
                parentStepID: "step_root",
                owner: .workerB,
                status: .running,
                title: "Stress launch risks",
                summary: "Surface edge cases and rollback needs."
            )
        ],
        tasks: [
            AgentTask(
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
                owner: .workerB,
                parentStepID: "step_checks",
                title: "Stress launch risks",
                goal: "Surface failure modes",
                expectedOutput: "Concise risk summary",
                contextSummary: "Look for rollback and monitoring gaps.",
                toolPolicy: .enabled,
                status: .running,
                liveStatusText: "Checking rollback",
                liveSummary: "The current draft still needs an explicit rollback gate and one monitoring checkpoint.",
                liveEvidence: ["Rollback gate is not named yet."],
                liveConfidence: .medium
            ),
            AgentTask(
                owner: .workerC,
                parentStepID: "step_root",
                title: "Check completeness",
                goal: "Find missing launch gates",
                expectedOutput: "Short completeness notes",
                contextSummary: "Keep the answer structured and complete.",
                toolPolicy: .reasoningOnly,
                status: .queued
            )
        ],
        decisions: [
            AgentDecision(
                kind: .triage,
                title: "Delegate",
                summary: "Run one bounded validation wave before synthesis."
            )
        ],
        evidence: ["Worker A already converged on additive rollout."],
        activeTaskIDs: [],
        outcome: "In progress"
    )
}
