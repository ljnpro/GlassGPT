import ChatDomain
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

        assertViewSnapshots(named: "agent-running-milestone-updates") {
            AgentView(viewModel: runningViewModel)
        }

        assertViewSnapshots(named: "agent-running-collapsed") {
            AgentView(
                viewModel: runningViewModel,
                initialLiveSummaryExpanded: false
            )
        }

        let reconnectingViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        _ = makeRunningAgentConversationSamples(in: reconnectingViewModel)
        reconnectingViewModel.processSnapshot.recoveryState = .reconnecting
        assertViewSnapshots(named: "agent-running-reconnecting-restored") {
            AgentView(viewModel: reconnectingViewModel)
        }

        let replayingViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        _ = makeRunningAgentConversationSamples(in: replayingViewModel)
        replayingViewModel.processSnapshot.recoveryState = .replayingCheckpoint
        assertViewSnapshots(named: "agent-running-replaying-checkpoint") {
            AgentView(viewModel: replayingViewModel)
        }

        let waitingViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        _ = makeRunningAgentConversationSamples(in: waitingViewModel)
        waitingViewModel.currentStage = .finalSynthesis
        waitingViewModel.processSnapshot.activity = .synthesis
        waitingViewModel.processSnapshot.leaderLiveStatus = "Waiting for tool results"
        waitingViewModel.processSnapshot.leaderLiveSummary = "Waiting for the last tool result before synthesis continues."
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

        let completedProcessViewModel = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        _ = makeRunningAgentConversationSamples(in: completedProcessViewModel)
        completedProcessViewModel.currentStage = .finalSynthesis
        completedProcessViewModel.processSnapshot.activity = .completed
        completedProcessViewModel.processSnapshot.leaderLiveStatus = "Done"
        completedProcessViewModel.processSnapshot.leaderLiveSummary = ""
        completedProcessViewModel.isRunning = true
        completedProcessViewModel.isStreaming = true
        completedProcessViewModel.currentThinkingText = "Checking supporting evidence before the final answer."
        completedProcessViewModel.activeToolCalls = [
            ToolCallInfo(
                id: "agent_visible_search",
                type: .webSearch,
                status: .searching,
                queries: ["launch checklist"]
            )
        ]
        assertViewSnapshots(named: "agent-completed-process-done-visible-synthesis-searching") {
            AgentView(viewModel: completedProcessViewModel)
        }
    }
}
