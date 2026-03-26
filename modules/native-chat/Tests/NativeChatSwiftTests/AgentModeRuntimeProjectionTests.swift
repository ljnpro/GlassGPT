import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeRuntimeProjectionTests {
    @Test func `agent final synthesis shows waiting while tools are still active after reasoning`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        controller.currentThinkingText = "Checking the accepted findings while tool results finish."
        controller.currentStreamingText = ""
        controller.isThinking = false
        controller.isStreaming = true
        controller.activeToolCalls = [
            ToolCallInfo(id: "ws_live", type: .webSearch, status: .searching, queries: ["rollout checklist"])
        ]

        #expect(controller.thinkingPresentationState == .waiting)

        controller.activeToolCalls = [
            ToolCallInfo(id: "ws_done", type: .webSearch, status: .completed, queries: ["rollout checklist"])
        ]
        controller.isStreaming = false

        #expect(controller.thinkingPresentationState == .completed)
    }

    @Test func `recent updates stay milestone only while leader and worker previews stream`() {
        var snapshot = AgentProcessProjector.makeInitialRunSnapshot(
            draftMessageID: UUID(),
            latestUserMessageID: UUID()
        )
        let initialUpdates = snapshot.processSnapshot.recentUpdateItems

        AgentProcessProjector.updateLeaderLivePreview(
            status: "Scoping the request",
            summary: "Shaping the first plan.",
            on: &snapshot
        )
        AgentProcessProjector.updateLeaderLivePreview(
            status: "Scoping the request",
            summary: "Splitting the work into bounded tracks.",
            on: &snapshot
        )

        let task = AgentTask(
            id: "task_worker_b",
            owner: .workerB,
            parentStepID: "step_root",
            title: "Stress launch risks",
            goal: "Surface failure modes",
            expectedOutput: "Concise risk notes",
            contextSummary: "Keep the answer safe.",
            toolPolicy: .enabled,
            status: .queued
        )
        AgentProcessProjector.queueTasks([task], on: &snapshot)
        let milestoneCount = snapshot.processSnapshot.recentUpdateItems.count
        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: "Searching",
            summary: "Checking rollback wording.",
            evidence: ["Rollback gate is missing."],
            confidence: .medium,
            risks: ["Rollback wording is implicit."],
            on: &snapshot
        )
        AgentProcessProjector.updateTaskLivePreview(
            taskID: task.id,
            statusText: "Searching",
            summary: "Checking monitoring wording.",
            evidence: ["Monitoring checkpoint is too vague."],
            confidence: .medium,
            risks: ["Monitoring wording is implicit."],
            on: &snapshot
        )

        #expect(initialUpdates.count == 1)
        #expect(snapshot.processSnapshot.recentUpdateItems.count == milestoneCount)
        #expect(snapshot.processSnapshot.recentUpdateItems.allSatisfy { update in
            !update.summary.contains("rollback wording") && !update.summary.contains("monitoring wording")
        })
    }

    @Test func `visible synthesis tool activity does not mutate completed agent process`() throws {
        let controller = try makeTestAgentController(streamClient: QueuedOpenAIStreamClient(scriptedStreams: []))
        let conversation = Conversation(modeRawValue: ConversationMode.agent.rawValue)
        conversation.mode = .agent
        let user = Message(role: .user, content: "Finish the answer.", conversation: conversation)
        let draft = Message(role: .assistant, content: "", conversation: conversation, isComplete: false)
        conversation.messages = [user, draft]

        let processSnapshot = AgentProcessSnapshot(
            activity: .completed,
            currentFocus: "Leader completed the internal council.",
            leaderAcceptedFocus: "Leader completed the internal council.",
            leaderLiveStatus: "Done",
            leaderLiveSummary: "Accepted findings are ready for the final answer.",
            stopReason: .sufficientAnswer,
            outcome: "Completed"
        )
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
                processSnapshot: processSnapshot,
                visibleSynthesisPresentation: AgentVisibleSynthesisPresentation(
                    statusText: "Writing final answer",
                    summaryText: "Writing final answer from accepted findings.",
                    recoveryState: .reconnecting
                ),
                isStreaming: true
            )
        )

        try AgentVisibleSynthesisEventApplier.apply(
            .webSearchStarted("visible_search"),
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: controller.runCoordinator
        )

        #expect(execution.snapshot.processSnapshot.activity == .completed)
        #expect(execution.snapshot.processSnapshot.leaderLiveStatus == "Done")
        #expect(execution.snapshot.visibleSynthesisPresentation?.statusText == "Searching the web")
        #expect(execution.snapshot.visibleSynthesisPresentation?.recoveryState == .idle)
    }

    @Test func `beginning visible synthesis freezes the internal council projection`() {
        var snapshot = AgentRunSnapshot(
            currentStage: .crossReview,
            phase: .leaderReview,
            draftMessageID: UUID(),
            latestUserMessageID: UUID(),
            processSnapshot: AgentProcessSnapshot(
                activity: .reviewing,
                currentFocus: "Reviewing worker findings.",
                leaderAcceptedFocus: "Accepted findings are ready.",
                leaderLiveStatus: "Reviewing worker results",
                leaderLiveSummary: "Reviewing worker findings before the final answer."
            )
        )

        AgentVisibleSynthesisProjector.begin(on: &snapshot)

        #expect(snapshot.currentStage == .finalSynthesis)
        #expect(snapshot.phase == .finalSynthesis)
        #expect(snapshot.processSnapshot.activity == .completed)
        #expect(snapshot.processSnapshot.leaderLiveStatus == "Done")
        #expect(snapshot.processSnapshot.recentUpdateItems.contains(where: {
            $0.kind == .councilCompleted
        }))
        #expect(snapshot.visibleSynthesisPresentation?.statusText == "Writing final answer")
    }
}
