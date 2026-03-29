import BackendContracts
import ChatDomain
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
struct BackendConversationSupportCoverageTests {
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
