import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRuntimeTests {
    @Test func `agent mode reuses persisted response ids across follow up turns`() async throws {
        let transport = ScriptedAgentCouncilTransport(
            turns: [
                AgentTurnScript(
                    leaderResponseID: "leader_brief_1",
                    roundOneResponseIDs: [
                        .workerA: "worker_a_round_1",
                        .workerB: "worker_b_round_1",
                        .workerC: "worker_c_round_1"
                    ],
                    revisionResponseIDs: [
                        .workerA: "worker_a_revision_1",
                        .workerB: "worker_b_revision_1",
                        .workerC: "worker_c_revision_1"
                    ]
                ),
                AgentTurnScript(
                    leaderResponseID: "leader_brief_2",
                    roundOneResponseIDs: [
                        .workerA: "worker_a_round_2",
                        .workerB: "worker_b_round_2",
                        .workerC: "worker_c_round_2"
                    ],
                    revisionResponseIDs: [
                        .workerA: "worker_a_revision_2",
                        .workerB: "worker_b_revision_2",
                        .workerC: "worker_c_revision_2"
                    ]
                )
            ]
        )
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [
            [
                .responseCreated("leader_final_1"),
                .textDelta("Final answer 1"),
                .completed("Final answer 1", nil, nil)
            ],
            [
                .responseCreated("leader_final_2"),
                .textDelta("Final answer 2"),
                .completed("Final answer 2", nil, nil)
            ]
        ])
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        #expect(controller.sendMessage(text: "How should we ship this?"))
        try await waitUntil {
            !controller.isRunning && controller.messages.last?.content == "Final answer 1"
        }

        #expect(controller.sendMessage(text: "What changes for the follow up?"))
        try await waitUntil {
            !controller.isRunning && controller.messages.last?.content == "Final answer 2"
        }

        let finalState = try #require(controller.currentConversation?.agentConversationState)
        #expect(finalState.responseID(for: .leader) == "leader_final_2")
        #expect(finalState.responseID(for: .workerA) == "worker_a_revision_2")
        #expect(finalState.responseID(for: .workerB) == "worker_b_revision_2")
        #expect(finalState.responseID(for: .workerC) == "worker_c_revision_2")

        let recordedRequests = await transport.requests()
        let requestBodies = recordedRequests.compactMap(previousResponseID(from:))

        #expect(requestBodies.contains("leader_final_1"))
        #expect(requestBodies.contains("worker_a_revision_1"))
        #expect(requestBodies.contains("worker_b_revision_1"))
        #expect(requestBodies.contains("worker_c_revision_1"))
    }

    @Test func `starting new agent conversation detaches active execution and rebinding avoids retry banner`() async throws {
        let transport = ScriptedAgentCouncilTransport(turns: [AgentTurnScript.singleTurn()])
        let streamClient = ControlledOpenAIStreamClient()
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        #expect(controller.sendMessage(text: "Keep this running"))
        try await waitUntil(timeout: 5) {
            controller.currentStage == .finalSynthesis && streamClient.activeStreamCount == 1
        }

        let runningConversation = try #require(controller.currentConversation)
        controller.startNewConversation()

        #expect(controller.currentConversation == nil)
        #expect(controller.messages.isEmpty)
        #expect(controller.errorMessage == nil)
        #expect(controller.sessionRegistry.execution(for: runningConversation.id) != nil)

        controller.loadConversation(runningConversation)
        #expect(controller.currentConversation?.id == runningConversation.id)
        #expect(controller.isRunning == true)
        #expect(controller.errorMessage == nil)

        streamClient.yield(.responseCreated("leader_final_detached"))
        streamClient.yield(.textDelta("Detached answer"))
        streamClient.yield(.completed("Detached answer", nil, nil))
        streamClient.finishStream()

        try await waitUntil {
            !controller.isRunning && controller.messages.last?.content == "Detached answer"
        }
        #expect(controller.errorMessage == nil)
    }

    @Test func `retry banner only appears when no live session and no recoverable background snapshot exists`() async throws {
        let transport = ScriptedAgentCouncilTransport(turns: [AgentTurnScript.singleTurn()])
        let streamClient = ControlledOpenAIStreamClient()
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        #expect(controller.sendMessage(text: "Keep running"))
        try await waitUntil(timeout: 5) {
            controller.currentStage == .finalSynthesis && streamClient.activeStreamCount == 1
        }

        let runningConversation = try #require(controller.currentConversation)
        controller.startNewConversation()
        controller.loadConversation(runningConversation)
        #expect(controller.errorMessage == nil)

        streamClient.yield(.responseCreated("leader_final_retry"))
        streamClient.yield(.textDelta("Recovered visibly"))
        streamClient.yield(.completed("Recovered visibly", nil, nil))
        streamClient.finishStream()
        try await waitUntil {
            !controller.isRunning && controller.messages.last?.content == "Recovered visibly"
        }

        let incompleteConversation = Conversation(
            title: "Incomplete",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        incompleteConversation.mode = .agent
        let user = Message(role: .user, content: "What happened?", conversation: incompleteConversation)
        let draft = Message(role: .assistant, content: "", conversation: incompleteConversation, isComplete: false)
        incompleteConversation.messages = [user, draft]
        incompleteConversation.agentConversationState = AgentConversationState(
            currentStage: nil,
            configuration: AgentConversationConfiguration(),
            activeRun: nil
        )
        controller.modelContext.insert(incompleteConversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        controller.loadConversation(incompleteConversation)
        #expect(controller.errorMessage == AgentConversationCoordinator.retryBannerMessage)
    }
}
