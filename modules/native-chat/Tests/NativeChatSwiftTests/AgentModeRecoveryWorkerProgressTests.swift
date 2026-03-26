import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRecoveryWorkerProgressTests {
    @Test func `worker recovery state clears on the first resumed worker delta`() async throws {
        let harness = try makeWorkerRecoveryHarness(
            title: "Worker Recovery Progress",
            taskID: "task_resume_worker"
        )

        let workerBody = """
        [STATUS]
        Checking worker b
        [/STATUS]
        [SUMMARY]
        Worker B recovered the rollback gap and one monitoring hole.
        [/SUMMARY]
        [EVIDENCE]
        - Rollback wording is still implicit.
        [/EVIDENCE]
        [CONFIDENCE]
        high
        [/CONFIDENCE]
        [RISKS]
        - Monitoring checkpoint remains vague.
        [/RISKS]
        [FOLLOW_UP]
        [/FOLLOW_UP]
        """

        harness.continuation.yield(.responseCreated("worker_b_resumed"))
        harness.continuation.yield(.textDelta(workerBody))

        try await waitUntil(timeout: 5) {
            harness.execution.snapshot.processSnapshot.recoveryState == .idle &&
                harness.execution.snapshot.processSnapshot.tasks.first?.liveSummary?.contains("rollback gap") == true &&
                !harness.execution.needsForegroundResume
        }

        harness.continuation.yield(.completed(workerBody, nil, nil))
        harness.continuation.finish()
        let result = try #require(try await harness.consumer.value)

        #expect(harness.execution.snapshot.processSnapshot.recoveryState == .idle)
        #expect(result.task.resultSummary?.contains("rollback gap") == true)
        #expect(!harness.execution.needsForegroundResume)
    }

    @Test func `worker recovery state stays reconnecting until resumed worker progress arrives`() async throws {
        let harness = try makeWorkerRecoveryHarness(
            title: "Worker Recovery Start",
            taskID: "task_resume_worker_start"
        )

        await Task.yield()
        #expect(harness.execution.snapshot.processSnapshot.recoveryState == .reconnecting)
        #expect(harness.execution.needsForegroundResume)

        let workerBody = """
        [STATUS]
        Checking worker b
        [/STATUS]
        [SUMMARY]
        Worker B recovered one rollback gap.
        [/SUMMARY]
        [EVIDENCE]
        - Rollback wording is still implicit.
        [/EVIDENCE]
        [CONFIDENCE]
        high
        [/CONFIDENCE]
        [RISKS]
        [/RISKS]
        [FOLLOW_UP]
        [/FOLLOW_UP]
        """

        harness.continuation.yield(.completed(workerBody, nil, nil))
        harness.continuation.finish()
        _ = try #require(try await harness.consumer.value)
    }
}

private struct AgentWorkerRecoveryHarness {
    let execution: AgentExecutionState
    let continuation: AsyncStream<StreamEvent>.Continuation
    let consumer: Task<AgentWorkerExecutionResult?, Error>
}

@MainActor
private func makeWorkerRecoveryHarness(
    title: String,
    taskID: String
) throws -> AgentWorkerRecoveryHarness {
    let controller = try makeTestAgentController(
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
    )
    let conversation = Conversation(
        title: title,
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

    let task = AgentTask(
        id: taskID,
        owner: .workerB,
        parentStepID: "step_root",
        title: "Check risk notes",
        goal: "Recover the worker findings",
        expectedOutput: "Concise risk notes",
        contextSummary: "Focus on rollback and monitoring gaps.",
        toolPolicy: .enabled,
        status: .running
    )
    var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
        draftMessageID: draft.id,
        latestUserMessageID: user.id,
        configuration: AgentConversationConfiguration(backgroundModeEnabled: true)
    )
    snapshot.currentStage = .workersRoundOne
    snapshot.phase = .workerWave
    snapshot.processSnapshot.tasks = [task]
    snapshot.processSnapshot.activeTaskIDs = [task.id]
    AgentProcessProjector.updateRecoveryState(.reconnecting, on: &snapshot)
    conversation.agentConversationState = AgentConversationState(
        currentStage: .workersRoundOne,
        configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
        activeRun: snapshot
    )
    controller.modelContext.insert(conversation)
    controller.modelContext.insert(user)
    controller.modelContext.insert(draft)

    let (stream, continuation) = makeTestAsyncStream() as (
        stream: AsyncStream<StreamEvent>,
        continuation: AsyncStream<StreamEvent>.Continuation
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
    let consumer = Task {
        try await controller.workerRuntime.consumeTaskStream(
            stream,
            task: task,
            role: .workerB,
            configuration: AgentConversationConfiguration(backgroundModeEnabled: true),
            conversation: conversation,
            execution: execution,
            initialState: AgentWorkerStreamState(
                responseID: "worker_b_resumed",
                rawText: "",
                toolCalls: [],
                citations: []
            )
        )
    }

    return AgentWorkerRecoveryHarness(
        execution: execution,
        continuation: continuation,
        consumer: consumer
    )
}
