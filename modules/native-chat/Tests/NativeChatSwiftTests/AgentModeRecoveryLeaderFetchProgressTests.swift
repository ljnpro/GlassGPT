import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryLeaderFetchProgressTests {
    @Test func `leader fetch recovery clears liveness on completed recovery result`() async throws {
        let transport = StubOpenAITransport()
        let responseID = "leader_triage_fetch_resume"
        let responseURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/\(responseID)")
        )
        let leaderBody = """
        [STATUS]
        Scoping the request
        [/STATUS]
        [FOCUS]
        Recovered leader planning from a completed fetch result.
        [/FOCUS]
        [DECISION]
        delegate
        [/DECISION]
        [PLAN]
        step_root || root || leader || running || Shape answer || Rebuild the worker wave.
        [/PLAN]
        [TASKS]
        workerA || step_root || enabled || Check scope || Validate the first path || Return concise notes
        [/TASKS]
        [DECISION_NOTE]
        Resume delegation from the completed fetch result.
        [/DECISION_NOTE]
        """
        try await transport.enqueue(
            data: makeFetchResponseData(status: .completed, text: leaderBody),
            url: responseURL
        )
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )

        let conversation = Conversation(
            title: "Leader Fetch Recovery Progress",
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: true,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        conversation.mode = .agent
        let user = Message(role: .user, content: "Resume the planning phase.", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages = [user, draft]

        let prepared = PreparedAgentTurn(
            apiKey: "sk-test",
            conversation: conversation,
            draft: draft,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            latestUserText: user.content,
            userMessageID: user.id,
            draftMessageID: draft.id,
            attachmentsToUpload: []
        )
        let execution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            apiKey: "sk-test",
            service: controller.serviceFactory(),
            snapshot: AgentRunSnapshot(
                currentStage: .leaderBrief,
                phase: .leaderTriage,
                draftMessageID: draft.id,
                latestUserMessageID: user.id,
                runConfiguration: AgentConversationConfiguration(backgroundModeEnabled: true),
                processSnapshot: AgentProcessProjector.makeInitialRunSnapshot(
                    draftMessageID: draft.id,
                    latestUserMessageID: user.id,
                    configuration: AgentConversationConfiguration(backgroundModeEnabled: true)
                ).processSnapshot
            )
        )
        execution.markNeedsForegroundResume()

        let result = try await controller.runCoordinator.recoverLeaderPlanningPhase(
            .triage,
            prepared: prepared,
            execution: execution,
            existingTicket: AgentRunTicket(
                role: .leader,
                phase: .leaderTriage,
                responseID: responseID,
                backgroundEligible: true
            ),
            baseInput: [],
            allowReplayFromCheckpoint: true
        )

        #expect(result.directive.decision == .delegate)
        #expect(execution.snapshot.processSnapshot.recoveryState == .idle)
        #expect(!execution.needsForegroundResume)
    }
}
