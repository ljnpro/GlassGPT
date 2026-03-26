import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryWorkerReplayTests {
    @Test func `background recovery replays the current worker wave when resume is exhausted`() async throws {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: OpenAIServiceError.requestFailed("offline"))
        await transport.enqueue(error: OpenAIServiceError.requestFailed("still offline"))
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_unused",
                    reviewResponseID: "leader_review_after_worker_replay",
                    taskResponseIDs: [
                        .workerB: "worker_b_replayed"
                    ],
                    finalResponseID: "leader_final_after_worker_replay",
                    finalAnswer: "Worker wave replayed answer"
                )
            ]
        )
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        let conversation = Conversation(
            title: "Replay Worker Wave",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Recover the worker wave", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        let queuedTask = AgentTask(
            id: "task_risks",
            owner: .workerB,
            parentStepID: "step_risk",
            title: "Stress launch risks",
            goal: "Surface the launch risks",
            expectedOutput: "Concise risk notes",
            contextSummary: "Check rollback and monitoring wording.",
            toolPolicy: .enabled,
            status: .running
        )
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            workerBResponseID: "worker_b_previous",
            currentStage: .workersRoundOne,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: AgentRunSnapshot(
                currentStage: .workersRoundOne,
                phase: .workerWave,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                leaderBriefSummary: "Resume the active worker wave.",
                processSnapshot: AgentProcessSnapshot(
                    activity: .delegation,
                    currentFocus: "Leader is waiting on the active worker wave.",
                    leaderAcceptedFocus: "Leader is waiting on the active worker wave.",
                    leaderLiveStatus: "Delegating work",
                    leaderLiveSummary: "Waiting for the recovered worker wave before review.",
                    plan: [
                        AgentPlanStep(
                            id: "step_risk",
                            owner: .workerB,
                            status: .running,
                            title: "Stress launch risks",
                            summary: "Surface rollback and monitoring gaps."
                        )
                    ],
                    tasks: [queuedTask],
                    activeTaskIDs: ["task_risks"]
                ),
                workerBTicket: AgentRunTicket(
                    role: .workerB,
                    phase: .workerWave,
                    taskID: queuedTask.id,
                    responseID: "worker_b_stale",
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
            !controller.isRunning && controller.messages.last?.content == "Worker wave replayed answer"
        }

        let instructions = try streamClient.recordedRequests.map { request in
            try #require(scriptedRequestPayload(from: request)["instructions"] as? String)
        }
        #expect(instructions.contains(where: { $0.contains("You are Worker B") }))
        #expect(controller.processSnapshot.recoveryState == .idle)
        #expect(controller.errorMessage == nil)
    }
}
