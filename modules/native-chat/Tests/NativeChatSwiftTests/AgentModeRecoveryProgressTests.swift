import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryProgressTests {
    @Test func `leader recovery state stays reconnecting until resumed planning progress arrives`() async throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(
            title: "Leader Recovery Start",
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

        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true)
        )
        snapshot.phase = .leaderTriage
        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &snapshot)
        conversation.agentConversationState = AgentConversationState(
            leaderResponseID: "leader_previous",
            currentStage: .leaderBrief,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: snapshot
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

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
            snapshot: snapshot
        )
        execution.markNeedsForegroundResume()
        let (stream, continuation) = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let consumer = Task {
            try await controller.runCoordinator.consumeLeaderPlanningStream(
                stream,
                planningPhase: .triage,
                prepared: prepared,
                execution: execution,
                initialState: HiddenLeaderStreamState(
                    responseID: "leader_triage_resumed",
                    checkpointBaseResponseID: "leader_previous",
                    lastSequenceNumber: 7,
                    rawText: "",
                    toolCalls: []
                )
            )
        }

        await Task.yield()
        #expect(execution.snapshot.processSnapshot.recoveryState == .reconnecting)
        #expect(execution.needsForegroundResume)

        let leaderBody = """
        [STATUS]
        Scoping the request
        [/STATUS]
        [FOCUS]
        Resume delegation from the recovered checkpoint.
        [/FOCUS]
        [DECISION]
        finish
        [/DECISION]
        [PLAN]
        step_root || root || leader || completed || Shape answer || Recovered directly.
        [/PLAN]
        [TASKS]
        [/TASKS]
        [DECISION_NOTE]
        The checkpoint already contains enough context to answer.
        [/DECISION_NOTE]
        [STOP_REASON]
        Answer completed.
        [/STOP_REASON]
        """
        continuation.yield(.completed(leaderBody, nil, nil))
        continuation.finish()
        _ = try #require(try await consumer.value)
    }

    @Test func `leader recovery state clears on the first resumed planning delta`() async throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(
            title: "Leader Recovery Progress",
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

        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: draft.id,
            latestUserMessageID: user.id,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true)
        )
        snapshot.phase = .leaderTriage
        AgentProcessProjector.updateRecoveryState(.reconnecting, on: &snapshot)
        conversation.agentConversationState = AgentConversationState(
            currentStage: .leaderBrief,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            activeRun: snapshot
        )
        controller.modelContext.insert(conversation)
        controller.modelContext.insert(user)
        controller.modelContext.insert(draft)

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
            snapshot: snapshot
        )
        execution.markNeedsForegroundResume()
        let (stream, continuation) = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let leaderBody = """
        [STATUS]
        Scoping the request
        [/STATUS]
        [FOCUS]
        Shaping the first worker wave from the recovered checkpoint.
        [/FOCUS]
        [DECISION]
        delegate
        [/DECISION]
        [PLAN]
        step_root || root || leader || running || Shape answer || Rebuild the first worker wave.
        [/PLAN]
        [TASKS]
        workerA || step_root || enabled || Check scope || Validate the first path || Return concise notes
        [/TASKS]
        [DECISION_NOTE]
        Resume delegation from the recovered checkpoint.
        [/DECISION_NOTE]
        """

        let consumer = Task {
            try await controller.runCoordinator.consumeLeaderPlanningStream(
                stream,
                planningPhase: .triage,
                prepared: prepared,
                execution: execution,
                initialState: HiddenLeaderStreamState(
                    responseID: "leader_triage_resumed",
                    lastSequenceNumber: 7,
                    rawText: "",
                    toolCalls: []
                )
            )
        }

        continuation.yield(.responseCreated("leader_triage_resumed"))
        continuation.yield(.textDelta(leaderBody))

        try await waitUntil(timeout: 5) {
            execution.snapshot.processSnapshot.recoveryState == .idle &&
                execution.snapshot.processSnapshot.leaderLiveSummary.contains("recovered checkpoint") &&
                !execution.needsForegroundResume
        }

        continuation.yield(.completed(leaderBody, nil, nil))
        continuation.finish()
        let result = try #require(try await consumer.value)

        #expect(execution.snapshot.processSnapshot.recoveryState == .idle)
        #expect(result.directive.decision == .delegate)
        #expect(!execution.needsForegroundResume)
    }
}
