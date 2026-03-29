import BackendClient
import Foundation

@MainActor
package extension BackendChatController {
    /// Processes a batch of SSE events, coalescing text deltas into single mutations.
    func flushChatStreamBatch(
        _ batch: [SSEEvent],
        conversationServerID _: String
    ) async throws {
        var textDeltas: [String] = []
        var thinkingDeltas: [String] = []

        for event in batch {
            switch event.event {
            case "delta":
                if let delta = decodeChatPayload(event, as: ChatTextDeltaPayload.self)?.textDelta {
                    textDeltas.append(delta)
                }
            case "thinking_delta":
                if let delta = decodeChatPayload(event, as: ChatThinkingDeltaPayload.self)?.thinkingDelta {
                    thinkingDeltas.append(delta)
                    isThinking = true
                }
            case "thinking_done":
                isThinking = false
            case "tool_call_update":
                applyChatToolCallUpdate(from: event)
            case "citations_update":
                applyChatCitationsUpdate(from: event)
            case "file_path_annotations_update":
                applyChatFilePathAnnotationsUpdate(from: event)
            case "status":
                applyChatStatus(from: event)
            case "stage":
                applyChatStage(from: event)
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
}

// MARK: - Batch-specific payload types (package-visible for batch handler)

/// Payload for text delta events in chat stream batches.
package struct ChatTextDeltaPayload: Decodable {
    let textDelta: String?
}

/// Payload for thinking delta events in chat stream batches.
package struct ChatThinkingDeltaPayload: Decodable {
    let thinkingDelta: String?
}
