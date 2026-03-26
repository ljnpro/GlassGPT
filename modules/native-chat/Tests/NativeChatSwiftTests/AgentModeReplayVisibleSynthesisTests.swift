import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeReplayVisibleSynthesisTests {
    @Test func `resume replaces stale execution and replays visible synthesis from checkpoint when response id is unavailable`()
        async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "unused_triage",
                    reviewResponseID: "unused_review",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_replay",
                    finalAnswer: "Replayed final answer"
                )
            ]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)

        let conversation = Conversation(
            title: "Replay Visible Synthesis",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(
            role: .user,
            content: "Continue the answer from the accepted findings.",
            conversation: conversation
        )
        let draft = Message(
            role: .assistant,
            content: "Old partial answer",
            thinking: "Old partial reasoning",
            conversation: conversation,
            isComplete: false
        )
        conversation.messages = [user, draft]

        let activeRun = AgentRunSnapshot(
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
                leaderLiveSummary: "The internal Agent council is complete.",
                stopReason: .sufficientAnswer,
                outcome: "Done"
            ),
            leaderTicket: AgentRunTicket(
                role: .leader,
                phase: .finalSynthesis,
                responseID: "leader_final_stale",
                checkpointBaseResponseID: "leader_review_base",
                backgroundEligible: true
            ),
            currentStreamingText: "Old partial answer",
            currentThinkingText: "Old partial reasoning",
            visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                statusText: "Reconnecting",
                summaryText: "Recovering the final answer from the accepted findings.",
                recoveryState: .reconnecting
            ),
            isStreaming: true
        )
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_review_base",
            currentStage: .finalSynthesis,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: activeRun
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)
        controller.currentConversation = conversation

        let staleExecution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            apiKey: "sk-test",
            service: controller.serviceFactory(),
            snapshot: activeRun
        )
        staleExecution.markNeedsForegroundResume()
        controller.sessionRegistry.register(staleExecution, visible: true)

        await controller.runCoordinator.resumePersistedRunIfNeeded(conversation)

        let resumedExecution = try #require(controller.sessionRegistry.execution(for: conversation.id))
        #expect(resumedExecution !== staleExecution)

        try await waitUntil(timeout: 10) {
            controller.messages.last?.content == "Replayed final answer"
                && controller.messages.last?.isComplete == true
                && controller.errorMessage == nil
        }

        #expect(controller.messages.last?.content == "Replayed final answer")
        #expect(controller.messages.last?.content.contains("Old partial answer") == false)
        let previousResponseIDs = streamClient.recordedRequests.compactMap(previousResponseID(from:))
        #expect(previousResponseIDs.first == "leader_review_base")
        #expect(!previousResponseIDs.contains("leader_final_stale"))
    }

    @Test func `standard mode resume also replays visible synthesis from checkpoint when response id is unavailable`()
        async throws {
        let streamClient = ScriptedAgentCouncilStreamClient(
            turns: [
                AgentTurnScript(
                    triageResponseID: "unused_triage_standard",
                    reviewResponseID: "unused_review_standard",
                    taskResponseIDs: [:],
                    finalResponseID: "leader_final_standard_replay",
                    finalAnswer: "Standard replayed final answer"
                )
            ]
        )
        let controller = try makeTestAgentController(streamClient: streamClient)

        let conversation = Conversation(
            title: "Standard Replay Visible Synthesis",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(
            role: .user,
            content: "Resume the visible synthesis without background mode.",
            conversation: conversation
        )
        let draft = Message(
            role: .assistant,
            content: "Old partial answer",
            thinking: "Old partial reasoning",
            conversation: conversation,
            isComplete: false
        )
        conversation.messages = [user, draft]

        let activeRun = AgentRunSnapshot(
            currentStage: .finalSynthesis,
            phase: .finalSynthesis,
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: false),
            processSnapshot: AgentProcessSnapshot(
                activity: .completed,
                currentFocus: "Leader completed the internal Agent council.",
                leaderAcceptedFocus: "Leader completed the internal Agent council.",
                leaderLiveStatus: "Done",
                leaderLiveSummary: "The internal Agent council is complete.",
                stopReason: .sufficientAnswer,
                outcome: "Done"
            ),
            leaderTicket: AgentRunTicket(
                role: .leader,
                phase: .finalSynthesis,
                responseID: "leader_final_standard_stale",
                checkpointBaseResponseID: "leader_review_standard_base",
                backgroundEligible: false
            ),
            currentStreamingText: "Old partial answer",
            currentThinkingText: "Old partial reasoning",
            visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                statusText: "Reconnecting",
                summaryText: "Recovering the final answer from the accepted findings.",
                recoveryState: .reconnecting
            ),
            isStreaming: true
        )
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_review_standard_base",
            currentStage: .finalSynthesis,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: false),
            activeRun: activeRun
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)
        controller.currentConversation = conversation

        let staleExecution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            apiKey: "sk-test",
            service: controller.serviceFactory(),
            snapshot: activeRun
        )
        staleExecution.markNeedsForegroundResume()
        controller.sessionRegistry.register(staleExecution, visible: true)

        await controller.runCoordinator.resumePersistedRunIfNeeded(conversation)

        let resumedExecution = try #require(controller.sessionRegistry.execution(for: conversation.id))
        #expect(resumedExecution !== staleExecution)

        try await waitUntil(timeout: 10) {
            controller.messages.last?.content == "Standard replayed final answer"
                && controller.messages.last?.isComplete == true
                && controller.errorMessage == nil
        }

        #expect(controller.messages.last?.content == "Standard replayed final answer")
        #expect(controller.messages.last?.content.contains("Old partial answer") == false)
        let previousResponseIDs = streamClient.recordedRequests.compactMap(previousResponseID(from:))
        #expect(previousResponseIDs.first == "leader_review_standard_base")
        #expect(!previousResponseIDs.contains("leader_final_standard_stale"))
    }
}
