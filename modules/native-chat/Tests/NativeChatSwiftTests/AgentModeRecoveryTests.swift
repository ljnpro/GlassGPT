import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryTests {
    @Test func `launch bootstrap resumes restored background agent conversation without waiting for surface appearance`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_bootstrap",
                    reviewResponseID: "leader_review_bootstrap",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_bootstrap",
                    finalAnswer: "Recovered from launch bootstrap"
                )
            ]
        )
        let controller = try makeTestAgentController(
            streamClient: streamClient,
            bootstrapPolicy: .live
        ) { context in
            let conversation = Conversation(
                title: "Bootstrap Agent",
                modeRawValue: ConversationMode.agent.rawValue,
                model: ModelType.gpt5_4.rawValue,
                reasoningEffort: ReasoningEffort.high.rawValue,
                backgroundModeEnabled: true,
                serviceTierRawValue: ServiceTier.flex.rawValue
            )
            conversation.mode = .agent
            let user = Message(role: .user, content: "Recover on launch", conversation: conversation)
            let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
            conversation.messages = [user, draft]
            conversation.agentConversationState = AgentConversationState(
                currentStage: .crossReview,
                configuration: AgentConversationConfiguration(
                    backgroundModeEnabled: true,
                    serviceTier: .flex
                ),
                activeRun: AgentRunSnapshot(
                    currentStage: .crossReview,
                    phase: .leaderReview,
                    draftMessageID: draft.id,
                    latestUserMessageID: user.id,
                    runConfiguration: AgentConversationConfiguration(
                        backgroundModeEnabled: true,
                        serviceTier: .flex
                    ),
                    leaderBriefSummary: "Resume the accepted worker discussion.",
                    processSnapshot: AgentProcessSnapshot(
                        activity: .reviewing,
                        currentFocus: "Leader is reviewing persisted worker findings.",
                        leaderAcceptedFocus: "Leader is reviewing persisted worker findings.",
                        leaderLiveStatus: "Reviewing worker results",
                        leaderLiveSummary: "Reviewing persisted worker findings before final synthesis.",
                        evidence: ["Recovered worker evidence is still valid."]
                    ),
                    workersRoundOneSummaries: [
                        AgentWorkerSummary(role: .workerA, summary: "Keep the answer practical."),
                        AgentWorkerSummary(role: .workerB, summary: "Call out the main risk."),
                        AgentWorkerSummary(role: .workerC, summary: "Check completeness.")
                    ],
                    workersRoundOneProgress: [
                        AgentWorkerProgress(role: .workerA, status: .completed),
                        AgentWorkerProgress(role: .workerB, status: .completed),
                        AgentWorkerProgress(role: .workerC, status: .completed)
                    ]
                )
            )
            context.insert(conversation)
            context.insert(user)
            context.insert(draft)
        }

        func latestAssistantMessage() -> Message? {
            controller.currentConversation?
                .messages
                .sorted(by: { $0.createdAt < $1.createdAt })
                .last(where: { $0.role == .assistant })
        }

        try await waitUntil(timeout: 10) {
            latestAssistantMessage()?.content == "Recovered from launch bootstrap"
                && latestAssistantMessage()?.isComplete == true
        }

        #expect(controller.currentConversation?.mode == .agent)
        #expect(controller.errorMessage == nil)
    }

    @Test func `background recovery resumes hidden stages from persisted snapshot`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_hidden_resume",
                    reviewResponseID: "leader_review_hidden_resume",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_hidden_resume",
                    finalAnswer: "Hidden recovery answer"
                )
            ]
        )
        let controller = try makeTestAgentController(
            streamClient: streamClient
        )

        let conversation = Conversation(
            title: "Resume Hidden",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Resume me", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_hidden_prev",
            workerAResponseID: "worker_a_prev",
            workerBResponseID: "worker_b_prev",
            workerCResponseID: "worker_c_prev",
            currentStage: .crossReview,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: AgentRunSnapshot(
                currentStage: .crossReview,
                phase: .leaderReview,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                leaderBriefSummary: "Use the safest path.",
                processSnapshot: AgentProcessSnapshot(
                    activity: .reviewing,
                    currentFocus: "Leader is reviewing the recovered worker findings.",
                    leaderAcceptedFocus: "Leader is reviewing the recovered worker findings.",
                    leaderLiveStatus: "Reviewing worker results",
                    leaderLiveSummary: "Reviewing recovered worker findings before the final answer.",
                    evidence: ["Recovered worker evidence remains sufficient."]
                ),
                workersRoundOneSummaries: [
                    AgentWorkerSummary(role: .workerA, summary: "Round A"),
                    AgentWorkerSummary(role: .workerB, summary: "Round B"),
                    AgentWorkerSummary(role: .workerC, summary: "Round C")
                ],
                workersRoundOneProgress: [
                    AgentWorkerProgress(role: .workerA, status: .completed),
                    AgentWorkerProgress(role: .workerB, status: .completed),
                    AgentWorkerProgress(role: .workerC, status: .completed)
                ]
            )
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        controller.loadConversation(conversation)
        controller.handleSurfaceAppearance()
        try await waitUntil(timeout: 10) {
            !controller.isRunning && controller.messages.last?.content == "Hidden recovery answer"
        }

        #expect(conversation.agentConversationState?.activeRun == nil)
        #expect(conversation.messages.last?.isComplete == true)
    }
}
