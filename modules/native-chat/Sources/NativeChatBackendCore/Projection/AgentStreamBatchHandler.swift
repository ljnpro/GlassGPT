import BackendClient
import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import Foundation

@MainActor
package extension BackendAgentController {
    /// Processes a batch of SSE events, coalescing text deltas into single mutations.
    func flushAgentStreamBatch(
        _ batch: [SSEEvent],
        conversationServerID _: String,
        runID _: String
    ) async throws {
        var textDeltas: [String] = []
        var thinkingDeltas: [String] = []

        for event in batch {
            switch event.event {
            case "delta":
                if let delta = decodeAgentPayload(event, as: AgentTextDeltaPayload.self)?.textDelta {
                    textDeltas.append(delta)
                }
            case "thinking_delta":
                if let delta = decodeAgentPayload(event, as: AgentThinkingDeltaPayload.self)?.thinkingDelta {
                    thinkingDeltas.append(delta)
                    isThinking = true
                }
            case "thinking_done":
                isThinking = false
            case "tool_call_update":
                applyAgentToolCallUpdate(from: event)
            case "citations_update":
                applyAgentCitationsUpdate(from: event)
            case "file_path_annotations_update":
                applyAgentFilePathAnnotationsUpdate(from: event)
            case "process_update":
                applyAgentProcessUpdate(from: event)
            case "task_update":
                applyAgentTaskUpdate(from: event)
            case "status":
                applyAgentStatus(from: event)
            case "stage":
                applyAgentStage(from: event)
            default:
                break
            }
        }

        if !textDeltas.isEmpty {
            currentStreamingText += textDeltas.joined()
        }
        if !thinkingDeltas.isEmpty {
            currentThinkingText += thinkingDeltas.joined()
        }
    }

    func applyAgentProcessUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(
            event,
            as: AgentProcessUpdatePayload.self,
            configure: { $0.dateDecodingStrategy = .iso8601 }
        ) else {
            return
        }
        processSnapshot = payload.processSnapshot
    }

    func applyAgentTaskUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(
            event,
            as: AgentTaskUpdatePayload.self,
            configure: { $0.dateDecodingStrategy = .iso8601 }
        ) else {
            return
        }
        var snapshot = processSnapshot
        snapshot.tasks.removeAll { $0.id == payload.task.id }
        snapshot.tasks.append(payload.task)
        processSnapshot = snapshot
    }
}

// MARK: - Batch-specific payload types (package-visible for batch handler)

/// Payload for text delta events in agent stream batches.
package struct AgentTextDeltaPayload: Decodable {
    let textDelta: String?
}

/// Payload for thinking delta events in agent stream batches.
package struct AgentThinkingDeltaPayload: Decodable {
    let thinkingDelta: String?
}

/// Payload for process update events in agent stream batches.
package struct AgentProcessUpdatePayload: Decodable {
    let processSnapshot: AgentProcessSnapshot
}

/// Payload for task update events in agent stream batches.
package struct AgentTaskUpdatePayload: Decodable {
    let task: AgentTask
}
