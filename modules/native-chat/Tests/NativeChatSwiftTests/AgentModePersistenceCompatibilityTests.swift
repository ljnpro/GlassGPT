import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModePersistenceCompatibilityTests {
    @Test func `legacy recent update strings decode into semantic milestone items`() throws {
        let payloadString = """
        {
          "activity": "delegation",
          "currentFocus": "Leader delegated a validation wave.",
          "leaderAcceptedFocus": "Leader delegated a validation wave.",
          "leaderLiveStatus": "Leader review",
          "leaderLiveSummary": "Comparing worker results.",
          "recentUpdates": [
            "Started Agent run",
            "Worker A completed."
          ],
          "outcome": "In progress"
        }
        """
        let payload = try #require(payloadString.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AgentProcessSnapshot.self, from: payload)

        #expect(decoded.recentUpdates == ["Started Agent run", "Worker A completed."])
        #expect(decoded.recentUpdateItems.map(\.summary) == ["Started Agent run", "Worker A completed."])
        #expect(decoded.recentUpdateItems.allSatisfy { $0.kind == .legacy })
    }

    @Test func `agent run snapshot round trips visible synthesis presentation and semantic updates`() throws {
        let snapshot = AgentRunSnapshot(
            currentStage: .finalSynthesis,
            phase: .finalSynthesis,
            draftMessageID: UUID(),
            latestUserMessageID: UUID(),
            runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
            processSnapshot: AgentProcessSnapshot(
                activity: .completed,
                currentFocus: "Leader completed the internal Agent council.",
                leaderAcceptedFocus: "Leader completed the internal Agent council.",
                leaderLiveStatus: "Done",
                leaderLiveSummary: "The internal Agent council is complete.",
                recentUpdateItems: [
                    AgentProcessUpdate(
                        kind: .councilCompleted,
                        source: .leader,
                        phase: .completed,
                        summary: "Council completed"
                    )
                ],
                outcome: "Done"
            ),
            leaderTicket: AgentRunTicket(
                role: .leader,
                phase: .finalSynthesis,
                responseID: "resp_final_live",
                checkpointBaseResponseID: "resp_council_base",
                backgroundEligible: true
            ),
            currentStreamingText: "Partial answer",
            currentThinkingText: "Reasoning from accepted findings.",
            visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                statusText: "Searching the web",
                summaryText: "Checking supporting evidence before the final answer.",
                recoveryState: .reconnecting
            ),
            activeToolCalls: [
                ToolCallInfo(id: "ws_visible", type: .webSearch, status: .searching, queries: ["launch checklist"])
            ],
            isStreaming: true
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AgentRunSnapshot.self, from: data)

        #expect(decoded.visibleSynthesisPresentation == snapshot.visibleSynthesisPresentation)
        #expect(decoded.processSnapshot.recentUpdateItems == snapshot.processSnapshot.recentUpdateItems)
        #expect(decoded.activeToolCalls == snapshot.activeToolCalls)
        #expect(decoded.leaderTicket?.checkpointBaseResponseID == "resp_council_base")
    }

    @Test func `legacy phase less final synthesis snapshot decodes back to final synthesis when streaming content exists`() throws {
        let payloadString = """
        {
          "currentStage": "finalSynthesis",
          "draftMessageID": "\(UUID())",
          "latestUserMessageID": "\(UUID())",
          "processSnapshot": {
            "activity": "completed",
            "currentFocus": "Leader completed the internal council.",
            "leaderAcceptedFocus": "Leader completed the internal council.",
            "leaderLiveStatus": "Done",
            "leaderLiveSummary": "Accepted findings are ready.",
            "outcome": "Completed"
          },
          "currentStreamingText": "Partial answer",
          "isStreaming": true
        }
        """
        let payload = try #require(payloadString.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AgentRunSnapshot.self, from: payload)

        #expect(decoded.phase == .finalSynthesis)
        #expect(decoded.currentStreamingText == "Partial answer")
    }

    @Test func `fallback resumable snapshot keeps council done while visible synthesis remains separate`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(
            title: "Fallback Visible Recovery",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Finish the answer from the accepted findings.", conversation: conversation)
        let draft = Message(
            role: .assistant,
            content: "Partial answer",
            thinking: "Partial reasoning",
            conversation: conversation,
            isComplete: false
        )
        conversation.messages = [user, draft]

        let snapshot = controller.runCoordinator.resumableSnapshot(in: conversation, draft: draft)

        #expect(snapshot.processSnapshot.activity == .completed)
        #expect(snapshot.processSnapshot.leaderLiveStatus == "Done")
        #expect(snapshot.visibleSynthesisPresentation?.statusText == "Writing final answer")
        #expect(snapshot.currentStreamingText == "Partial answer")
    }

    @Test func `resumable snapshot backfills legacy leader checkpoint base response id`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(
            title: "Legacy Leader Replay",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Resume the leader phase.", conversation: conversation)
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
                leaderTicket: AgentRunTicket(
                    role: .leader,
                    phase: .leaderTriage,
                    responseID: "leader_stale",
                    backgroundEligible: true
                )
            )
        )

        let snapshot = controller.runCoordinator.resumableSnapshot(in: conversation, draft: draft)
        #expect(snapshot.leaderTicket?.checkpointBaseResponseID == "leader_previous")
    }

    @Test func `resumable snapshot backfills legacy worker checkpoint base response id`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(
            title: "Legacy Worker Replay",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Resume the worker phase.", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
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
                workerBTicket: AgentRunTicket(
                    role: .workerB,
                    phase: .workerWave,
                    responseID: "worker_b_stale",
                    backgroundEligible: true
                )
            )
        )

        let snapshot = controller.runCoordinator.resumableSnapshot(in: conversation, draft: draft)
        #expect(snapshot.workerBTicket?.checkpointBaseResponseID == "worker_b_previous")
    }
}
