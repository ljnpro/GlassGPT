import BackendClient
import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatAgentControllerCoverageTests {
    @Test func `agent controller handles signed out blocked and reset states`() throws {
        let signedOut = try makeNativeChatHarness(signedIn: false).makeAgentController()

        #expect(!signedOut.sendMessage(text: ""))
        #expect(!signedOut.sendMessage(text: "Plan"))
        #expect(signedOut.errorMessage == "Sign in with Apple in Settings to use Agent mode.")

        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let controller = signedInHarness.makeAgentController()
        controller.selectedImageData = Data([0x01])
        #expect(!controller.sendMessage(text: "Plan"))
        #expect(controller.errorMessage == "Attachments are not available yet.")

        controller.selectedImageData = nil
        controller.isRunning = true
        #expect(!controller.sendMessage(text: "Plan"))
        controller.isRunning = false

        let attachment = FileAttachment(filename: "doc.pdf", fileType: "pdf")
        controller.pendingAttachments = [attachment]
        controller.removePendingAttachment(attachment)
        #expect(controller.pendingAttachments.isEmpty)

        controller.currentStreamingText = "stream"
        controller.currentThinkingText = "thinking"
        controller.processSnapshot = AgentProcessSnapshot(activity: .triage, leaderLiveStatus: "Queued")
        controller.startNewConversation()
        #expect(controller.messages.isEmpty)
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.processSnapshot.activity == .triage)
        #expect(controller.processSnapshot.leaderLiveStatus.isEmpty)
        #expect(controller.processSnapshot.tasks.isEmpty)

        controller.stopGeneration()
        #expect(!controller.isRunning)
        #expect(!controller.isThinking)
    }

    @Test func `agent controller configuration and visible state sync behave correctly`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeAgentController()
        let conversation = makeHarnessConversation(mode: .agent)
        conversation.agentWorkerReasoningEffort = .medium
        let foreignConversation = makeHarnessConversation(accountID: "other", mode: .agent)

        controller.applyConfiguration(
            AgentConversationConfiguration(
                leaderReasoningEffort: .high,
                workerReasoningEffort: .medium,
                serviceTier: .flex
            )
        )

        controller.setCurrentConversation(conversation)
        controller.persistVisibleConfiguration()
        #expect(conversation.reasoningEffort == ReasoningEffort.high.rawValue)
        #expect(conversation.agentWorkerReasoningEffortRawValue == ReasoningEffort.medium.rawValue)
        #expect(conversation.serviceTierRawValue == ServiceTier.flex.rawValue)

        controller.messages = [makeBackendMessageSurface(isComplete: false, includeTrace: true)]
        controller.syncVisibleState()
        #expect(controller.currentConversationID == conversation.id)

        #expect(!controller.applyLoadedConversation(foreignConversation))
        #expect(controller.errorMessage == "This conversation belongs to a different account.")
        #expect(controller.applyLoadedConversation(conversation))
        controller.hydrateConfigurationFromConversation()
        #expect(controller.workerReasoningEffort == .medium)

        await controller.bootstrap()
        #expect(controller.currentConversationID != nil || controller.messages.isEmpty)
    }

    @Test func `agent controller exposes detached process and streaming surfaces before draft synthesis attaches`() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeAgentController()

        controller.isRunning = true
        controller.isThinking = true
        controller.currentThinkingText = "Comparing worker output"
        controller.activeToolCalls = [
            ToolCallInfo(id: "tool_live", type: .codeInterpreter, status: .interpreting)
        ]
        controller.processSnapshot = AgentProcessSnapshot(
            activity: .reviewing,
            currentFocus: "Review worker output",
            leaderAcceptedFocus: "Review worker output",
            leaderLiveStatus: "Reviewing",
            leaderLiveSummary: "Leader is reviewing"
        )

        #expect(controller.liveDraftMessageID == nil)
        #expect(controller.shouldShowDetachedStreamingBubble)
        #expect(controller.shouldShowDetachedLiveSummaryCard)

        controller.messages = [
            makeBackendMessageSurface(
                role: .assistant,
                content: "",
                isComplete: false,
                includeTrace: false
            )
        ]

        #expect(controller.liveDraftMessageID != nil)
        #expect(!controller.shouldShowDetachedStreamingBubble)
        #expect(!controller.shouldShowDetachedLiveSummaryCard)
    }

    @Test func `agent controller stream path applies process task and synthesis payloads before finalizing`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeAgentController()
        let conversation = makeHarnessConversation(serverID: "conv_agent_stream", mode: .agent)
        controller.setCurrentConversation(conversation)
        controller.syncVisibleState()
        harness.client.detail = try makeAgentConversationDetailSnapshot(
            conversationID: "conv_agent_stream",
            runID: "run_agent_stream",
            assistantContent: "Final synthesis body"
        )
        harness.client.streamEvents = try makeAgentSuccessStreamEvents()
        harness.client.queuedRunResponses["run_agent_stream"] = [
            makeAgentRun(status: .running, stage: .finalSynthesis, summary: "Synthesizing final answer")
        ]

        await controller.streamOrPollRun(
            conversationServerID: "conv_agent_stream",
            runID: "run_agent_stream",
            selectionToken: controller.visibleSelectionToken
        )

        #expect(harness.client.fetchRunCallCount == 2)
        #expect(controller.messages.count == 2)
        #expect(controller.messages.last?.content == "Final synthesis body")
        #expect(controller.messages.last?.agentTrace != nil)
        #expect(controller.processSnapshot.leaderLiveStatus == "Completed")
        #expect(controller.processSnapshot.leaderLiveSummary == "Done")
        #expect(controller.processSnapshot.tasks.isEmpty)
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.activeToolCalls.isEmpty)
        #expect(controller.liveCitations.isEmpty)
        #expect(controller.liveFilePathAnnotations.isEmpty)
        #expect(!controller.shouldShowDetachedStreamingBubble)
        #expect(!controller.shouldShowDetachedLiveSummaryCard)
    }

    @Test func `agent controller falls back to polling when stream setup fails and preserves completed process state`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeAgentController()
        let conversation = makeHarnessConversation(serverID: "conv_agent_poll", mode: .agent)
        controller.setCurrentConversation(conversation)
        controller.syncVisibleState()
        harness.client.detail = try makeAgentConversationDetailSnapshot(
            conversationID: "conv_agent_poll",
            runID: "run_agent_poll",
            assistantContent: "Polling synthesis"
        )
        harness.client.streamSetupError = .unacceptableStatusCode(401)
        harness.client.queuedRunResponses["run_agent_poll"] = [
            makeAgentRun(status: .completed, stage: .finalSynthesis, summary: "Complete")
        ]

        await controller.streamOrPollRun(
            conversationServerID: "conv_agent_poll",
            runID: "run_agent_poll",
            selectionToken: controller.visibleSelectionToken
        )

        #expect(harness.client.fetchRunCallCount == 1)
        #expect(controller.messages.last?.content == "Polling synthesis")
        #expect(controller.processSnapshot.activity == .completed)
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.activeToolCalls.isEmpty)
        #expect(controller.liveCitations.isEmpty)
        #expect(controller.liveFilePathAnnotations.isEmpty)
        #expect(!controller.shouldShowDetachedStreamingBubble)
        #expect(!controller.shouldShowDetachedLiveSummaryCard)
    }
}
