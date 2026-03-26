import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryVisibleSynthesisProgressTests {
    @Test func `visible synthesis recovery clears on resumed response metadata before text arrives`() throws {
        let controller = try makeTestAgentController(
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = Conversation(modeRawValue: ConversationMode.agent.rawValue)
        conversation.mode = .agent
        let user = Message(role: .user, content: "Resume final synthesis.", conversation: conversation)
        let draft = Message(
            role: .assistant,
            content: "Partial final answer",
            thinking: "Accepted findings",
            conversation: conversation,
            responseId: "resp_visible_old",
            isComplete: false
        )
        conversation.messages = [user, draft]

        let execution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            apiKey: "sk-test",
            service: controller.serviceFactory(),
            snapshot: AgentRunSnapshot(
                currentStage: .finalSynthesis,
                phase: .finalSynthesis,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                processSnapshot: AgentProcessSnapshot(
                    activity: .completed,
                    currentFocus: "Leader completed the internal council.",
                    leaderAcceptedFocus: "Leader completed the internal council.",
                    leaderLiveStatus: "Done",
                    leaderLiveSummary: "Accepted findings are ready.",
                    stopReason: .sufficientAnswer,
                    outcome: "Completed"
                ),
                visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                    statusText: "Reconnecting",
                    summaryText: "Recovering the final answer.",
                    recoveryState: .reconnecting
                ),
                isStreaming: true
            )
        )

        try AgentVisibleSynthesisEventApplier.apply(
            .responseCreated("resp_visible_new"),
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: controller.runCoordinator
        )

        #expect(execution.snapshot.visibleSynthesisPresentation?.recoveryState == .idle)
        #expect(draft.responseId == "resp_visible_new")
        #expect(execution.snapshot.processSnapshot.activity == .completed)

        execution.snapshot.visibleSynthesisPresentation?.recoveryState = .reconnecting
        try AgentVisibleSynthesisEventApplier.apply(
            .sequenceUpdate(12),
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: controller.runCoordinator
        )

        #expect(execution.snapshot.visibleSynthesisPresentation?.recoveryState == .idle)
        #expect(draft.lastSequenceNumber == 12)
        #expect(execution.snapshot.processSnapshot.activity == .completed)
    }

    @Test func `visible synthesis recovery stays reconnecting until restarted synthesis emits progress`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "unused_triage",
                    reviewResponseID: "unused_review",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_live",
                    finalAnswer: "Recovered final answer"
                )
            ],
            controlledResponseIDs: ["leader_final_live"]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)
        let conversation = Conversation(
            title: "Visible Synthesis Start",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Finish from accepted findings.", conversation: conversation)
        let draft = Message(
            role: .assistant,
            content: "Old partial answer",
            thinking: "Old partial reasoning",
            conversation: conversation,
            isComplete: false
        )
        conversation.messages = [user, draft]
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        let execution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            apiKey: "sk-test",
            service: controller.serviceFactory(),
            snapshot: AgentRunSnapshot(
                currentStage: .finalSynthesis,
                phase: .finalSynthesis,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                processSnapshot: AgentProcessSnapshot(
                    activity: .completed,
                    currentFocus: "Leader completed the internal council.",
                    leaderAcceptedFocus: "Leader completed the internal council.",
                    leaderLiveStatus: "Done",
                    leaderLiveSummary: "Accepted findings are ready.",
                    stopReason: .sufficientAnswer,
                    outcome: "Completed"
                ),
                leaderTicket: AgentRunTicket(
                    role: .leader,
                    phase: .finalSynthesis,
                    responseID: "leader_final_stale",
                    checkpointBaseResponseID: "leader_review_checkpoint",
                    backgroundEligible: true
                ),
                visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                    statusText: "Reconnecting",
                    summaryText: "Recovering the final answer.",
                    recoveryState: .reconnecting
                ),
                isStreaming: true
            )
        )

        let consumer = Task {
            try await controller.runCoordinator.runVisibleLeaderSynthesis(
                apiKey: "sk-test",
                configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
                conversation: conversation,
                execution: execution,
                baseInput: AgentPromptBuilder.visibleConversationInput(from: conversation.messages),
                initialPresentation: AgentVisibleSynthesisPresentation(
                    statusText: "Reconnecting",
                    summaryText: "Recovering the final answer.",
                    recoveryState: .reconnecting
                ),
                previousResponseIDOverride: "leader_review_checkpoint"
            )
        }

        try await waitUntil(timeout: 5) {
            streamClient.activeStreamCount == 1
        }
        #expect(execution.snapshot.visibleSynthesisPresentation?.recoveryState == .reconnecting)

        streamClient.yield(.responseCreated("leader_final_live"), onResponseID: "leader_final_live")
        try await waitUntil(timeout: 5) {
            execution.snapshot.visibleSynthesisPresentation?.recoveryState == .idle
        }
        streamClient.yield(.textDelta("Recovered final answer"), onResponseID: "leader_final_live")
        streamClient.yield(.completed("Recovered final answer", nil, nil), onResponseID: "leader_final_live")
        streamClient.finishStream(responseID: "leader_final_live")
        try await consumer.value

        #expect(execution.snapshot.visibleSynthesisPresentation?.recoveryState == .idle)
    }
}
