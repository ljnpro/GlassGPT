import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryReplayLocalPassTests {
    @Test func `background recovery replays leader local pass from checkpoint and keeps the run phase local`() async throws {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: OpenAIServiceError.requestFailed("offline"))
        await transport.enqueue(error: OpenAIServiceError.requestFailed("still offline"))
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_unused_local_pass",
                    localPassResponseID: "leader_local_pass_replayed",
                    reviewResponseID: "leader_review_after_local_pass_replay",
                    taskResponseIDs: [
                        .workerA: "worker_a_after_local_pass_replay"
                    ],
                    finalResponseID: "leader_final_after_local_pass_replay",
                    finalAnswer: "Leader local pass replayed answer"
                )
            ]
        )
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        let conversation = Conversation(
            title: "Replay Local Pass",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Recover the local pass phase", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_previous",
            currentStage: .leaderBrief,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: AgentRunSnapshot(
                currentStage: .leaderBrief,
                phase: .leaderLocalPass,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                leaderBriefSummary: "Resume the short local pass before delegation.",
                processSnapshot: AgentProcessSnapshot(
                    activity: .localPass,
                    currentFocus: "Leader is tightening the next worker wave.",
                    leaderAcceptedFocus: "Leader is tightening the next worker wave.",
                    leaderLiveStatus: "Refining task briefs",
                    leaderLiveSummary: "Doing a short local pass before delegation."
                ),
                leaderTicket: AgentRunTicket(
                    role: .leader,
                    phase: .leaderLocalPass,
                    responseID: "leader_local_pass_stale",
                    backgroundEligible: true
                )
            )
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        controller.loadConversation(conversation)
        controller.handleSurfaceAppearance()
        try await waitUntil(timeout: 10) {
            !controller.isRunning && controller.messages.last?.content == "Leader local pass replayed answer"
        }

        let instructions = try streamClient.recordedRequests.map { request in
            try #require(scriptedRequestPayload(from: request)["instructions"] as? String)
        }
        let previousResponseIDs = streamClient.recordedRequests.compactMap(previousResponseID(from:))
        #expect(instructions.contains(where: { $0.contains("doing a short local pass before delegation") }))
        #expect(!instructions.contains(where: { $0.contains("dynamic Agent team. Work like a Codex leader coordinating subagents") }))
        #expect(previousResponseIDs.first == "leader_previous")
        #expect(controller.processSnapshot.recoveryState == .idle)
        #expect(controller.errorMessage == nil)
    }
}
