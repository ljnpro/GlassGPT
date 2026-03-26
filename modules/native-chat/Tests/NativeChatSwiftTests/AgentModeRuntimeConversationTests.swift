import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRuntimeConversationTests {
    @Test func `agent mode reuses persisted response ids across follow up turns`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_1",
                    reviewResponseID: "leader_review_1",
                    taskResponseIDs: [
                        .workerA: "worker_a_task_1",
                        .workerB: "worker_b_task_1",
                        .workerC: "worker_c_task_1"
                    ],
                    finalResponseID: "leader_final_1",
                    finalAnswer: "Final answer 1"
                ),
                AgentTurnScript(
                    triageResponseID: "leader_triage_2",
                    reviewResponseID: "leader_review_2",
                    taskResponseIDs: [
                        .workerA: "worker_a_task_2",
                        .workerB: "worker_b_task_2",
                        .workerC: "worker_c_task_2"
                    ],
                    finalResponseID: "leader_final_2",
                    finalAnswer: "Final answer 2"
                )
            ]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)

        #expect(controller.sendMessage(text: "How should we ship this?"))
        try await waitUntil(timeout: 10) {
            !controller.isRunning && controller.messages.last?.content == "Final answer 1"
        }

        #expect(controller.sendMessage(text: "What changes for the follow up?"))
        try await waitUntil(timeout: 10) {
            !controller.isRunning && controller.messages.last?.content == "Final answer 2"
        }

        let finalState = try #require(controller.currentConversation?.agentConversationState)
        #expect(finalState.responseID(for: .leader) == "leader_final_2")
        #expect(finalState.responseID(for: .workerA) == "worker_a_task_2")
        #expect(finalState.responseID(for: .workerB) == "worker_b_task_2")
        #expect(finalState.responseID(for: .workerC) == "worker_c_task_2")

        let requestBodies = streamClient.recordedRequests.compactMap(previousResponseID(from:))

        #expect(requestBodies.contains("leader_final_1"))
        #expect(requestBodies.contains("worker_a_task_1"))
        #expect(requestBodies.contains("worker_b_task_1"))
        #expect(requestBodies.contains("worker_c_task_1"))

        let trace = try #require(controller.messages.last?.agentTrace)
        #expect(trace.workerSummaries.count == 3)
        #expect(trace.processSnapshot?.decisions.count(where: { $0.title == "Finish" }) == 1)
    }

    @Test func `starting new agent conversation detaches active execution and rebinding avoids retry banner`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_detached",
                    reviewResponseID: "leader_review_detached",
                    taskResponseIDs: [
                        .workerA: "worker_a_task",
                        .workerB: "worker_b_task",
                        .workerC: "worker_c_task"
                    ],
                    finalResponseID: "leader_final_detached",
                    finalAnswer: "Detached answer"
                )
            ],
            controlledResponseIDs: ["leader_final_detached"]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)

        #expect(controller.sendMessage(text: "Keep this running"))
        try await waitUntil(timeout: 10) {
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

        streamClient.yield(.responseCreated("leader_final_detached"), onResponseID: "leader_final_detached")
        streamClient.yield(.textDelta("Detached answer"), onResponseID: "leader_final_detached")
        streamClient.yield(.completed("Detached answer", nil, nil), onResponseID: "leader_final_detached")
        streamClient.finishStream(responseID: "leader_final_detached")

        try await waitUntil(timeout: 10) {
            !controller.isRunning && controller.messages.last?.content == "Detached answer"
        }
        #expect(controller.errorMessage == nil)
    }

    @Test func `dormant conversations prefer automatic restart over retry banner when progress can be reconstructed`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "leader_triage_retry",
                    reviewResponseID: "leader_review_retry",
                    taskResponseIDs: [
                        .workerA: "worker_a_task",
                        .workerB: "worker_b_task",
                        .workerC: "worker_c_task"
                    ],
                    finalResponseID: "leader_final_retry",
                    finalAnswer: "Recovered visibly"
                )
            ],
            controlledResponseIDs: ["leader_final_retry"]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)

        #expect(controller.sendMessage(text: "Keep running"))
        try await waitUntil(timeout: 10) {
            controller.currentStage == .finalSynthesis && streamClient.activeStreamCount == 1
        }

        let runningConversation = try #require(controller.currentConversation)
        controller.startNewConversation()
        controller.loadConversation(runningConversation)
        #expect(controller.errorMessage == nil)

        streamClient.yield(.responseCreated("leader_final_retry"), onResponseID: "leader_final_retry")
        streamClient.yield(.textDelta("Recovered visibly"), onResponseID: "leader_final_retry")
        streamClient.yield(.completed("Recovered visibly", nil, nil), onResponseID: "leader_final_retry")
        streamClient.finishStream(responseID: "leader_final_retry")
        try await waitUntil(timeout: 10) {
            !controller.isRunning && controller.messages.last?.content == "Recovered visibly"
        }

        let restartableConversation = Conversation(
            title: "Restartable",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        restartableConversation.mode = .agent
        let user = Message(role: .user, content: "What happened?", conversation: restartableConversation)
        let draft = Message(role: .assistant, content: "", conversation: restartableConversation, isComplete: false)
        restartableConversation.messages = [user, draft]
        restartableConversation.agentConversationState = AgentConversationState(
            currentStage: nil,
            configuration: AgentConversationConfiguration(),
            activeRun: nil
        )
        controller.modelContext.insert(restartableConversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        controller.loadConversation(restartableConversation)
        #expect(controller.errorMessage == nil)
        #expect(controller.processSnapshot.activity == .triage)

        let failedConversation = Conversation(
            title: "Failed",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        failedConversation.mode = .agent
        let failedUser = Message(role: .user, content: "Can you recover?", conversation: failedConversation)
        let failedDraft = Message(
            role: .assistant,
            content: "",
            conversation: failedConversation,
            isComplete: false
        )
        failedConversation.messages = [failedUser, failedDraft]
        failedConversation.agentConversationState = AgentConversationState(
            currentStage: nil,
            configuration: AgentConversationConfiguration(),
            activeRun: AgentRunSnapshot(
                currentStage: .leaderBrief,
                phase: .failed,
                draftMessageID: failedDraft.id,
                latestUserMessageID: failedUser.id,
                processSnapshot: AgentProcessSnapshot(
                    activity: .failed,
                    currentFocus: "Leader planning lost its connection.",
                    leaderAcceptedFocus: "Leader planning lost its connection.",
                    leaderLiveStatus: "Failed",
                    leaderLiveSummary: "The Agent run cannot continue automatically."
                )
            )
        )
        controller.modelContext.insert(failedConversation)
        controller.modelContext.insert(failedUser)
        controller.modelContext.insert(failedDraft)

        controller.loadConversation(failedConversation)
        #expect(controller.errorMessage == nil)
        #expect(controller.processSnapshot.activity == .triage)
    }
}
