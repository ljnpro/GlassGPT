import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryLaunchTests {
    @Test func `background recovery fetches completed visible synthesis by response id`() async throws {
        let transport = StubOpenAITransport()
        let recoveredData = try makeFetchResponseData(
            status: .completed,
            text: "Recovered final answer",
            thinking: "Recovered reasoning"
        )
        await transport.enqueue(data: recoveredData)
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        let conversation = Conversation(
            title: "Recover Visible",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Recover final", conversation: conversation)
        let draft = Message(
            role: .assistant,
            content: "Partial",
            thinking: "Partial reasoning",
            conversation: conversation,
            responseId: "resp_visible_recovery",
            isComplete: false
        )
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_prev",
            currentStage: .finalSynthesis,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: AgentRunSnapshot(
                currentStage: .finalSynthesis,
                phase: .finalSynthesis,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                leaderBriefSummary: "Finish with the safe answer.",
                crossReviewSummaries: [
                    AgentWorkerSummary(role: .workerA, summary: "Cross A"),
                    AgentWorkerSummary(role: .workerB, summary: "Cross B"),
                    AgentWorkerSummary(role: .workerC, summary: "Cross C")
                ],
                currentStreamingText: "Partial",
                currentThinkingText: "Partial reasoning",
                isStreaming: true
            )
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        func latestAssistantMessage() -> Message? {
            conversation.messages
                .sorted(by: { $0.createdAt < $1.createdAt })
                .last(where: { $0.role == .assistant })
        }

        controller.loadConversation(conversation)
        controller.handleSurfaceAppearance()
        try await waitUntil(timeout: 10) {
            !controller.isRunning &&
                controller.messages.last?.content == "Recovered final answer" &&
                latestAssistantMessage()?.thinking == "Recovered reasoning"
        }

        #expect(latestAssistantMessage()?.thinking == "Recovered reasoning")
        #expect(controller.errorMessage == nil)
    }

    @Test func `launch bootstrap keeps standard mode checkpoint dormant instead of auto resuming`() async throws {
        let controller = try makeTestAgentController(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
            bootstrapPolicy: .live
        ) { context in
            let conversation = Conversation(
                title: "Dormant Agent",
                modeRawValue: ConversationMode.agent.rawValue,
                model: ModelType.gpt5_4.rawValue,
                reasoningEffort: ReasoningEffort.high.rawValue,
                backgroundModeEnabled: false,
                serviceTierRawValue: ServiceTier.standard.rawValue
            )
            conversation.mode = .agent
            let user = Message(role: .user, content: "Do not auto resume", conversation: conversation)
            let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
            conversation.messages = [user, draft]
            conversation.agentConversationState = AgentConversationState(
                currentStage: .leaderBrief,
                configuration: AgentConversationConfiguration(backgroundModeEnabled: false),
                activeRun: AgentRunSnapshot(
                    currentStage: .leaderBrief,
                    phase: .leaderTriage,
                    draftMessageID: draft.id,
                    latestUserMessageID: user.id,
                    runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: false),
                    processSnapshot: AgentProcessSnapshot(
                        activity: .triage,
                        currentFocus: "Leader is scoping the request.",
                        leaderAcceptedFocus: "Leader is scoping the request.",
                        leaderLiveStatus: "Scoping the request",
                        leaderLiveSummary: "Classifying the request and sketching the first plan."
                    )
                )
            )
            context.insert(conversation)
            context.insert(user)
            context.insert(draft)
        }

        try await waitUntil(timeout: 10) {
            controller.currentConversation?.title == "Dormant Agent"
                && controller.processSnapshot.leaderLiveStatus == "Scoping the request"
        }

        #expect(controller.isRunning == true)
        #expect(controller.currentConversation?.messages.last?.isComplete == false)
        #expect(controller.errorMessage == nil)
    }
}
