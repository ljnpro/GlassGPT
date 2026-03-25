import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModePersistenceTests {
    @Test func `conversation mode defaults to chat and agent payloads round trip`() {
        let conversation = Conversation()
        #expect(conversation.mode == .chat)
        #expect(conversation.agentConversationState == nil)

        var state = AgentConversationState()
        state.setResponseID("leader_resp", for: .leader)
        state.currentStage = .crossReview
        conversation.mode = .agent
        conversation.agentConversationState = state

        let trace = AgentTurnTrace(
            leaderBriefSummary: "Validate the migration plan.",
            workerSummaries: [
                AgentWorkerSummary(
                    role: .workerA,
                    summary: "Prefer the additive rollout.",
                    adoptedPoints: ["Keep the migration reversible."]
                )
            ],
            completedStage: .finalSynthesis,
            outcome: "Completed"
        )
        let message = Message(
            role: .assistant,
            content: "Final answer",
            agentTrace: trace
        )

        #expect(conversation.mode == .agent)
        #expect(conversation.agentConversationState?.responseID(for: .leader) == "leader_resp")
        #expect(conversation.agentConversationState?.currentStage == .crossReview)
        #expect(message.agentTrace == trace)
    }

    @Test func `tagged output parser extracts leader brief and worker adoption`() {
        let leaderBrief = AgentTaggedOutputParser.parseLeaderBrief(
            from: """
            [BRIEF]
            Focus on shipping an additive migration path.
            [/BRIEF]
            """
        )
        let revision = AgentTaggedOutputParser.parseWorkerRevision(
            from: """
            [SUMMARY]
            Prefer the staged rollout with parity checks.
            [/SUMMARY]
            [ADOPTED]
            - Keep rollback steps explicit.
            - Call out missing monitoring.
            [/ADOPTED]
            """
        )

        #expect(leaderBrief == "Focus on shipping an additive migration path.")
        #expect(revision.summary == "Prefer the staged rollout with parity checks.")
        #expect(revision.adoptedPoints == [
            "Keep rollback steps explicit.",
            "Call out missing monitoring."
        ])
    }

    @Test func `worker preview parser extracts partial streamed summaries`() {
        let preview = AgentTaggedOutputParser.parseWorkerTaskPreview(
            from: """
            [STATUS]
            Checking launch risks
            [/STATUS]
            [SUMMARY]
            The main issue is rollback visibility while the worker is still collecting evidence.
            [EVIDENCE]
            - Rollback gate is missing from the current draft.
            """
        )

        #expect(preview.status == "Checking launch risks")
        #expect(preview.summary == "The main issue is rollback visibility while the worker is still collecting evidence.")
        #expect(preview.evidence == ["Rollback gate is missing from the current draft."])
    }

    @Test func `final synthesis input includes accepted worker discussion bundle`() {
        let input = AgentPromptBuilder.finalSynthesisInput(
            baseInput: [],
            discussion: AgentPromptBuilder.FinalSynthesisDiscussion(
                leaderFocus: "Write the final rollout recommendation.",
                planHighlights: ["Validate rollback gates."],
                workerSummaries: [
                    AgentWorkerSummary(
                        role: .workerA,
                        summary: "Use an additive rollout with rollback gates.",
                        adoptedPoints: ["Keep parity checks visible."]
                    )
                ],
                adoptedEvidence: ["Parity checks stayed explicit."],
                remainingRisks: ["Monitoring is still thin."],
                stopReason: "Answer completed"
            )
        )

        let text = input.compactMap { message -> String? in
            guard case let .text(text) = message.content else { return nil }
            return text
        }.joined(separator: "\n")

        #expect(text.contains("Accepted worker discussion"))
        #expect(text.contains("Worker A: Use an additive rollout with rollback gates."))
        #expect(text.contains("Adopted evidence"))
        #expect(text.contains("Remaining risks to keep in mind"))
    }

    @Test func `history presenter labels agent conversations as Agent`() throws {
        let container = try makeInMemoryModelContainer()
        let modelContext = ModelContext(container)
        let appStore = NativeChatCompositionRoot(
            modelContext: modelContext,
            bootstrapPolicy: .testing
        ).makeAppStore()

        let agentConversation = Conversation(title: "Agent Review")
        agentConversation.mode = .agent
        let agentMessage = Message(
            role: .assistant,
            content: "Agent summary",
            conversation: agentConversation
        )
        agentConversation.messages = [agentMessage]
        modelContext.insert(agentConversation)
        modelContext.insert(agentMessage)
        try modelContext.save()

        appStore.historyPresenter.refresh()

        let row = try #require(
            appStore.historyPresenter.conversations.first(where: { $0.id == agentConversation.id })
        )
        #expect(row.modelDisplayName == "Agent")
    }

    @Test func `agent state decode preserves 4 12 0 migration defaults`() throws {
        let payload = try JSONEncoder().encode(
            LegacyAgentConversationStatePayload(
                leaderResponseID: "leader_old",
                currentStage: .workersRoundOne
            )
        )
        let state = try JSONDecoder().decode(AgentConversationState.self, from: payload)

        #expect(state.responseID(for: .leader) == "leader_old")
        #expect(state.currentStage == .workersRoundOne)
        #expect(state.configuration.leaderReasoningEffort == .high)
        #expect(state.configuration.workerReasoningEffort == .low)
        #expect(state.configuration.backgroundModeEnabled == false)
        #expect(state.configuration.serviceTier == .standard)
    }

    @Test func `agent settings persist separate defaults`() {
        let harness = makeTestSettingsScreenStoreHarness()

        harness.store.agentDefaults.defaultLeaderEffort = .xhigh
        harness.store.agentDefaults.defaultWorkerEffort = .medium
        harness.store.agentDefaults.defaultBackgroundModeEnabled = true
        harness.store.agentDefaults.defaultFlexModeEnabled = true

        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultAgentLeaderEffort)
                == ReasoningEffort.xhigh.rawValue
        )
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultAgentWorkerEffort)
                == ReasoningEffort.medium.rawValue
        )
        #expect(
            harness.settingsValueStore.bool(forKey: SettingsStore.Keys.defaultAgentBackgroundModeEnabled)
                == true
        )
        #expect(
            harness.settingsValueStore.string(forKey: SettingsStore.Keys.defaultAgentServiceTier)
                == ServiceTier.flex.rawValue
        )
    }

    @Test func `agent configuration persists into conversation payloads and shared projections`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let configuration = AgentConversationConfiguration(
            leaderReasoningEffort: .xhigh,
            workerReasoningEffort: .medium,
            backgroundModeEnabled: true,
            serviceTier: .flex
        )
        let conversation = Conversation(modeRawValue: ConversationMode.agent.rawValue)
        conversation.mode = .agent
        controller.modelContext.insert(conversation)
        controller.currentConversation = conversation
        controller.applyConfiguration(configuration)

        let persisted = try #require(conversation.agentConversationState)
        #expect(persisted.configuration == configuration)
        #expect(conversation.reasoningEffort == ReasoningEffort.xhigh.rawValue)
        #expect(conversation.backgroundModeEnabled == true)
        #expect(conversation.serviceTierRawValue == ServiceTier.flex.rawValue)
    }

    @Test func `persisted worker progress keeps round one and cross review separate`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(modeRawValue: ConversationMode.agent.rawValue)
        conversation.mode = .agent
        let user = Message(role: .user, content: "Audit the release plan.", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages = [user, draft]
        conversation.agentConversationState = AgentConversationState(
            currentStage: .crossReview,
            configuration: AgentConversationConfiguration(),
            activeRun: AgentRunSnapshot(
                currentStage: .crossReview,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                workersRoundOneProgress: [
                    AgentWorkerProgress(role: .workerA, status: .completed),
                    AgentWorkerProgress(role: .workerB, status: .completed),
                    AgentWorkerProgress(role: .workerC, status: .completed)
                ],
                crossReviewProgress: [
                    AgentWorkerProgress(role: .workerA, status: .completed),
                    AgentWorkerProgress(role: .workerB, status: .running),
                    AgentWorkerProgress(role: .workerC, status: .waiting)
                ]
            )
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

        controller.loadConversation(conversation)

        #expect(controller.currentStage == .crossReview)
        #expect(controller.workersRoundOneProgress.map(\.status) == [.completed, .completed, .completed])
        #expect(controller.crossReviewProgress.map(\.status) == [.completed, .running, .waiting])
    }
}
