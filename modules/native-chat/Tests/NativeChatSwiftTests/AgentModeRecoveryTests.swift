import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryTests {
    @Test func `background recovery resumes hidden stages from persisted snapshot`() async throws {
        let transport = ScriptedAgentCouncilTransport(turns: [AgentTurnScript.singleTurn()])
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [[
            .responseCreated("leader_final_hidden_resume"),
            .textDelta("Hidden recovery answer"),
            .completed("Hidden recovery answer", nil, nil)
        ]])
        let controller = try makeTestAgentController(
            transport: transport,
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
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                leaderBriefSummary: "Use the safest path.",
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
        try await waitUntil(timeout: 5) {
            !controller.isRunning && controller.messages.last?.content == "Hidden recovery answer"
        }

        #expect(conversation.agentConversationState?.activeRun == nil)
        #expect(conversation.messages.last?.isComplete == true)
    }

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
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
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
        try await waitUntil(timeout: 5) {
            !controller.isRunning &&
                controller.messages.last?.content == "Recovered final answer" &&
                latestAssistantMessage()?.thinking == "Recovered reasoning"
        }

        #expect(latestAssistantMessage()?.thinking == "Recovered reasoning")
        #expect(controller.errorMessage == nil)
    }
}
