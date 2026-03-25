import ChatPersistenceSwiftData
@testable import NativeChatComposition

@MainActor
extension SnapshotViewTests {
    func testAgentSnapshots() throws {
        let emptyViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: false)
        assertViewSnapshots(named: "agent-empty") {
            AgentView(viewModel: emptyViewModel)
        }

        let runningViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        _ = makeRunningAgentConversationSamples(in: runningViewModel)
        assertViewSnapshots(named: "agent-running") {
            AgentView(viewModel: runningViewModel)
        }

        assertViewSnapshots(named: "agent-running-collapsed") {
            AgentView(
                viewModel: runningViewModel,
                initialLiveSummaryExpanded: false
            )
        }

        let waitingViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        _ = makeRunningAgentConversationSamples(in: waitingViewModel)
        waitingViewModel.isThinking = false
        waitingViewModel.currentStreamingText = ""
        waitingViewModel.currentThinkingText = "Waiting for the last tool result before synthesis."
        assertViewSnapshots(named: "agent-running-waiting") {
            AgentView(viewModel: waitingViewModel)
        }

        let completedViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        let completedConversation = makeCompletedAgentConversationSamples(in: completedViewModel)
        assertViewSnapshots(named: "agent-completed-collapsed") {
            AgentView(viewModel: completedViewModel)
        }

        let expandedMessageIDs = Set(completedConversation.messages.map(\.id))
        assertViewSnapshots(named: "agent-completed-expanded") {
            AgentView(
                viewModel: completedViewModel,
                initialExpandedTraceMessageIDs: expandedMessageIDs
            )
        }
    }
}
