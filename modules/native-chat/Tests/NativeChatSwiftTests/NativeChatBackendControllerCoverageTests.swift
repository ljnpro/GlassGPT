import BackendContracts
import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatBackendControllerCoverageTests {
    @Test func `chat controller handles signed out blocked and reset states`() throws {
        let signedOut = try makeNativeChatHarness(signedIn: false).makeChatController()

        #expect(!signedOut.sendMessage(text: ""))
        #expect(!signedOut.sendMessage(text: "Hello"))
        #expect(signedOut.errorMessage == "Sign in with Apple in Settings to use chat.")

        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let controller = signedInHarness.makeChatController()
        controller.selectedImageData = Data([0x01])
        #expect(!controller.sendMessage(text: "Hello"))
        #expect(controller.errorMessage == "Attachments are not available in Beta 5.0 yet.")

        controller.selectedImageData = nil
        controller.pendingAttachments = [FileAttachment(filename: "doc.pdf", fileType: "pdf")]
        #expect(!controller.sendMessage(text: "Hello"))
        controller.pendingAttachments = []

        controller.isStreaming = true
        #expect(!controller.sendMessage(text: "Hello"))
        controller.isStreaming = false

        let attachment = FileAttachment(filename: "doc.pdf", fileType: "pdf")
        controller.pendingAttachments = [attachment]
        controller.removePendingAttachment(attachment)
        #expect(controller.pendingAttachments.isEmpty)

        controller.currentStreamingText = "text"
        controller.currentThinkingText = "thinking"
        controller.errorMessage = "error"
        controller.startNewConversation()
        #expect(controller.messages.isEmpty)
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.errorMessage == nil)

        controller.stopGeneration()
        #expect(!controller.isStreaming)
    }

    @Test func `chat controller conversation state syncs and validates account ownership`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        let conversation = makeHarnessConversation()
        let foreignConversation = makeHarnessConversation(accountID: "other")

        controller.setCurrentConversation(conversation)
        controller.applyConversationConfiguration(
            ConversationConfiguration(model: .gpt5_4_pro, reasoningEffort: .high, serviceTier: .flex)
        )
        controller.persistVisibleConfiguration()
        #expect(conversation.model == ModelType.gpt5_4_pro.rawValue)
        #expect(conversation.serviceTierRawValue == ServiceTier.flex.rawValue)

        controller.messages = [makeBackendMessageSurface()]
        controller.syncMessages()
        #expect(controller.currentConversationID == conversation.id)

        #expect(!controller.applyLoadedConversation(foreignConversation))
        #expect(controller.errorMessage == "This conversation belongs to a different account.")
        #expect(controller.applyLoadedConversation(conversation))

        await controller.bootstrap()
        #expect(controller.currentConversationID != nil || controller.messages.isEmpty)
    }

    @Test func `agent controller handles signed out blocked and reset states`() throws {
        let signedOut = try makeNativeChatHarness(signedIn: false).makeAgentController()

        #expect(!signedOut.sendMessage(text: ""))
        #expect(!signedOut.sendMessage(text: "Plan"))
        #expect(signedOut.errorMessage == "Sign in with Apple in Settings to use Agent mode.")

        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let controller = signedInHarness.makeAgentController()
        controller.selectedImageData = Data([0x01])
        #expect(!controller.sendMessage(text: "Plan"))
        #expect(controller.errorMessage == "Attachments are not available in Beta 5.0 yet.")

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

    @Test func `default conversation titles match expected labels`() {
        #expect(BackendConversationSupport.defaultConversationTitle(for: .chat) == "New Chat")
        #expect(BackendConversationSupport.defaultConversationTitle(for: .agent) == "New Agent")
    }

    @Test func `short effort labels cover all cases`() {
        #expect(BackendConversationSupport.shortLabel(for: .none) == "Off")
        #expect(BackendConversationSupport.shortLabel(for: .low) == "Low")
        #expect(BackendConversationSupport.shortLabel(for: .medium) == "Med")
        #expect(BackendConversationSupport.shortLabel(for: .high) == "High")
        #expect(BackendConversationSupport.shortLabel(for: .xhigh) == "Max")
    }

    @Test func `sorted messages returns empty for nil conversation`() {
        #expect(BackendConversationSupport.sortedMessages(in: nil).isEmpty)
    }

    @Test func `process snapshot maps all agent stages and terminal states`() {
        let leaderSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .running, stage: .leaderPlanning, summary: "Planning"),
            progressLabel: nil
        )
        #expect(leaderSnap.activity == .triage)
        #expect(leaderSnap.leaderLiveStatus == "Leader planning")

        let workerSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .running, stage: .workerWave, summary: "Working"),
            progressLabel: "Custom"
        )
        #expect(workerSnap.activity == .delegation)
        #expect(workerSnap.leaderLiveSummary == "Custom")

        let reviewSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .running, stage: .leaderReview, summary: "Review"),
            progressLabel: nil
        )
        #expect(reviewSnap.activity == .reviewing)

        let synthSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .running, stage: .finalSynthesis, summary: "Synthesizing"),
            progressLabel: nil
        )
        #expect(synthSnap.activity == .synthesis)

        let completedSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .completed, summary: "Done"),
            progressLabel: nil
        )
        #expect(completedSnap.activity == .completed)
        #expect(completedSnap.outcome == "Done")

        let failedSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .failed, summary: "Error"),
            progressLabel: nil
        )
        #expect(failedSnap.activity == .failed)

        let cancelledSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .cancelled),
            progressLabel: nil
        )
        #expect(cancelledSnap.activity == .failed)

        let queuedSnap = BackendConversationSupport.processSnapshot(
            for: makeAgentRun(status: .queued),
            progressLabel: nil
        )
        #expect(queuedSnap.activity == .triage)

        let nilSnap = BackendConversationSupport.processSnapshot(for: nil, progressLabel: nil)
        #expect(nilSnap.activity == .triage)
    }
}

private func makeAgentRun(
    status: RunStatusDTO,
    stage: AgentStageDTO? = nil,
    summary: String? = nil
) -> RunSummaryDTO {
    let now = Date.now
    return RunSummaryDTO(
        id: "run_1",
        conversationID: "conv_1",
        kind: .agent,
        status: status,
        stage: stage,
        createdAt: now,
        updatedAt: now,
        lastEventCursor: nil,
        visibleSummary: summary
    )
}
