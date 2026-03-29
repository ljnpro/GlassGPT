import BackendClient

@MainActor
extension BackendChatController: BackendConversationStreamProjecting {}

@MainActor
package extension BackendChatController {
    func applyStreamStatusEvent(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: StreamStatusPayload.self),
              let summary = payload.visibleSummary
        else {
            return
        }

        seedThinkingSummaryIfNeeded(summary)
    }

    func applyStreamStageEvent(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: StreamStagePayload.self),
              let summary = payload.visibleSummary,
              !summary.isEmpty
        else {
            return
        }

        replaceThinkingSummary(summary)
    }
}
