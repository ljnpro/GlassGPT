import BackendClient

@MainActor
package extension BackendAgentController {
    func applyModeSpecificStreamEvent(
        _ event: SSEEvent,
        conversationServerID _: String,
        runID _: String
    ) async throws -> BackendConversationStreamOutcome {
        switch event.event {
        case "process_update":
            applyAgentProcessUpdate(from: event)
        case "task_update":
            applyAgentTaskUpdate(from: event)
        default:
            break
        }
        return .continueLoop
    }
}
