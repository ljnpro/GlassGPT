import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeReplayVisibleSynthesisReplacementTests {
    @Test func `resume replaces mismatched live execution and replays visible synthesis from the persisted checkpoint`() async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "unused_triage_mismatch",
                    reviewResponseID: "unused_review_mismatch",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_mismatch_replay",
                    finalAnswer: "Recovered from the persisted checkpoint"
                )
            ]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)
        let fixture = makeVisibleSynthesisMismatchFixture(using: controller)
        controller.currentConversation = fixture.conversation

        let mismatchedExecution = makeMismatchedVisibleSynthesisExecution(
            controller: controller,
            fixture: fixture
        )
        controller.sessionRegistry.register(mismatchedExecution, visible: true)

        await controller.runCoordinator.resumePersistedRunIfNeeded(fixture.conversation)

        let resumedExecution = try #require(
            controller.sessionRegistry.execution(for: fixture.conversation.id)
        )
        #expect(resumedExecution !== mismatchedExecution)

        try await waitUntil(timeout: 10) {
            controller.messages.last?.content == "Recovered from the persisted checkpoint"
                && controller.messages.last?.isComplete == true
                && controller.errorMessage == nil
        }

        #expect(controller.messages.last?.content == "Recovered from the persisted checkpoint")
        #expect(controller.messages.last?.content.contains("Half written answer") == false)
        let previousResponseIDs = streamClient.recordedRequests.compactMap(previousResponseID(from:))
        #expect(previousResponseIDs.first == "leader_review_mismatch_base")
        #expect(!previousResponseIDs.contains("leader_final_wrong_live"))
    }
}

private struct VisibleSynthesisMismatchFixture {
    let conversation: Conversation
    let draft: Message
    let persistedRun: AgentRunSnapshot
}

@MainActor
private func makeVisibleSynthesisMismatchFixture(
    using controller: AgentController
) -> VisibleSynthesisMismatchFixture {
    let conversation = Conversation(
        title: "Mismatch Replay Visible Synthesis",
        modeRawValue: ConversationMode.agent.rawValue,
        model: ModelType.gpt5_4.rawValue,
        reasoningEffort: ReasoningEffort.high.rawValue,
        backgroundModeEnabled: true,
        serviceTierRawValue: ServiceTier.standard.rawValue
    )
    conversation.mode = .agent
    let user = Message(
        role: .user,
        content: "Recover the final answer from the persisted checkpoint.",
        conversation: conversation
    )
    let draft = Message(
        role: .assistant,
        content: "Half written answer",
        thinking: "Half written reasoning",
        conversation: conversation,
        isComplete: false
    )
    conversation.messages = [user, draft]

    let persistedRun = AgentRunSnapshot(
        currentStage: .finalSynthesis,
        phase: .finalSynthesis,
        draftMessageID: draft.id,
        latestUserMessageID: user.id,
        runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
        processSnapshot: AgentProcessSnapshot(
            activity: .completed,
            currentFocus: "Leader completed the internal Agent council.",
            leaderAcceptedFocus: "Leader completed the internal Agent council.",
            leaderLiveStatus: "Done",
            leaderLiveSummary: "Accepted findings are ready for the final answer.",
            stopReason: .sufficientAnswer,
            outcome: "Done"
        ),
        leaderTicket: AgentRunTicket(
            role: .leader,
            phase: .finalSynthesis,
            responseID: nil,
            checkpointBaseResponseID: "leader_review_mismatch_base",
            backgroundEligible: true
        ),
        currentStreamingText: "Half written answer",
        currentThinkingText: "Half written reasoning",
        visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
            statusText: "Reconnecting",
            summaryText: "Recovering the final answer from the accepted findings.",
            recoveryState: .reconnecting
        ),
        isStreaming: true
    )
    conversation.agentConversationState = AgentConversationState(
        leaderResponseID: "leader_review_mismatch_base",
        currentStage: .finalSynthesis,
        configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
        activeRun: persistedRun
    )
    controller.modelContext.insert(conversation)
    controller.modelContext.insert(user)
    controller.modelContext.insert(draft)

    return VisibleSynthesisMismatchFixture(
        conversation: conversation,
        draft: draft,
        persistedRun: persistedRun
    )
}

@MainActor
private func makeMismatchedVisibleSynthesisExecution(
    controller: AgentController,
    fixture: VisibleSynthesisMismatchFixture
) -> AgentExecutionState {
    let execution = AgentExecutionState(
        conversationID: fixture.conversation.id,
        draftMessageID: fixture.draft.id,
        latestUserMessageID: fixture.conversation.messages.first?.id ?? fixture.draft.id,
        apiKey: "sk-test",
        service: controller.serviceFactory(),
        snapshot: {
            var snapshot = fixture.persistedRun
            snapshot.leaderTicket = AgentRunTicket(
                role: .leader,
                phase: .finalSynthesis,
                responseID: "leader_final_wrong_live",
                checkpointBaseResponseID: "leader_review_wrong_base",
                backgroundEligible: true
            )
            return snapshot
        }()
    )
    execution.task = Task<Void, Never> {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
    }
    return execution
}
