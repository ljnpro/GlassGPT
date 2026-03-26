import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryReplayTests {
    @Test func `background recovery replays leader triage from checkpoint and continues with delegation`() async throws {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: OpenAIServiceError.requestFailed("offline"))
        await transport.enqueue(error: OpenAIServiceError.requestFailed("still offline"))
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_replayed",
                    reviewResponseID: "leader_review_after_triage_replay",
                    taskResponseIDs: [
                        .workerA: "worker_a_after_triage_replay",
                        .workerB: "worker_b_after_triage_replay",
                        .workerC: "worker_c_after_triage_replay"
                    ],
                    finalResponseID: "leader_final_after_triage_replay",
                    finalAnswer: "Leader triage replayed answer"
                )
            ]
        )
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        let conversation = Conversation(
            title: "Replay Triage",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Recover the triage phase", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_previous",
            currentStage: .leaderBrief,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: AgentRunSnapshot(
                currentStage: .leaderBrief,
                phase: .leaderTriage,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                leaderBriefSummary: "Resume the initial Agent triage.",
                processSnapshot: AgentProcessSnapshot(
                    activity: .triage,
                    currentFocus: "Leader is scoping the request and shaping the first plan.",
                    leaderAcceptedFocus: "Leader is scoping the request and shaping the first plan.",
                    leaderLiveStatus: "Scoping the request",
                    leaderLiveSummary: "Classifying the request and shaping the first plan."
                ),
                leaderTicket: AgentRunTicket(
                    role: .leader,
                    phase: .leaderTriage,
                    responseID: "leader_triage_stale",
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
            !controller.isRunning && controller.messages.last?.content == "Leader triage replayed answer"
        }

        let instructions = try streamClient.recordedRequests.map { request in
            try #require(scriptedRequestPayload(from: request)["instructions"] as? String)
        }
        let previousResponseIDs = streamClient.recordedRequests.compactMap(previousResponseID(from:))
        #expect(instructions.contains(where: { $0.contains("dynamic Agent team. Work like a Codex leader coordinating subagents") }))
        #expect(instructions.contains(where: { $0.contains("You are Worker A") }))
        #expect(instructions.contains(where: { $0.contains("reviewing delegated worker results") }))
        #expect(previousResponseIDs.first == "leader_previous")
        #expect(!previousResponseIDs.contains("leader_triage_stale"))
        #expect(controller.processSnapshot.recoveryState == .idle)
        #expect(controller.errorMessage == nil)
    }

    @Test func `background recovery replays leader review from checkpoint when resume is exhausted`() async throws {
        let transport = StubOpenAITransport()
        await transport.enqueue(error: OpenAIServiceError.requestFailed("offline"))
        await transport.enqueue(error: OpenAIServiceError.requestFailed("still offline"))
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_unused",
                    reviewResponseID: "leader_review_replayed",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_replayed",
                    finalAnswer: "Leader review replayed answer"
                )
            ]
        )
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        let conversation = Conversation(
            title: "Replay Review",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Recover the review phase", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        let completedTask = AgentTask(
            id: "task_answer",
            owner: .workerA,
            parentStepID: "step_root",
            title: "Draft strongest answer",
            goal: "Return the best answer path",
            expectedOutput: "Concise recommendation",
            contextSummary: "Keep the answer grounded.",
            toolPolicy: .enabled,
            status: .completed,
            resultSummary: "Use the safest rollout path.",
            result: AgentTaskResult(summary: "Use the safest rollout path.", evidence: ["Rollback stays explicit."])
        )
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_previous",
            currentStage: .crossReview,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: AgentRunSnapshot(
                currentStage: .crossReview,
                phase: .leaderReview,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                leaderBriefSummary: "Resume reviewing the accepted worker results.",
                processSnapshot: AgentProcessSnapshot(
                    activity: .reviewing,
                    currentFocus: "Leader is reviewing the recovered worker findings.",
                    leaderAcceptedFocus: "Leader is reviewing the recovered worker findings.",
                    leaderLiveStatus: "Reviewing worker results",
                    leaderLiveSummary: "Reviewing the recovered worker findings before final synthesis.",
                    plan: [
                        AgentPlanStep(
                            id: "step_root",
                            owner: .leader,
                            status: .running,
                            title: "Shape answer",
                            summary: "Review worker findings before answering."
                        )
                    ],
                    tasks: [completedTask],
                    evidence: ["Recovered worker evidence remains sufficient."]
                ),
                leaderTicket: AgentRunTicket(
                    role: .leader,
                    phase: .leaderReview,
                    responseID: "leader_review_stale",
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
            !controller.isRunning && controller.messages.last?.content == "Leader review replayed answer"
        }

        let instructions = try streamClient.recordedRequests.map { request in
            try #require(scriptedRequestPayload(from: request)["instructions"] as? String)
        }
        let previousResponseIDs = streamClient.recordedRequests.compactMap(previousResponseID(from:))
        #expect(instructions.contains(where: { $0.contains("reviewing delegated worker results") }))
        #expect(!instructions.contains(where: { $0.contains("dynamic Agent team. Work like a Codex leader coordinating subagents") }))
        #expect(previousResponseIDs.first == "leader_previous")
        #expect(controller.processSnapshot.recoveryState == .idle)
        #expect(controller.errorMessage == nil)
    }
}
