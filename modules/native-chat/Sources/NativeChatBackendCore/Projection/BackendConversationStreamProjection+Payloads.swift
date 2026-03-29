import BackendClient
import Foundation

@MainActor
package extension BackendConversationStreamProjecting {
    func streamTextDelta(from event: SSEEvent) -> String? {
        decodeStreamPayload(event, as: StreamTextDeltaPayload.self)?.textDelta
    }

    func streamThinkingDelta(from event: SSEEvent) -> String? {
        decodeStreamPayload(event, as: StreamThinkingDeltaPayload.self)?.thinkingDelta
    }

    func applyStreamTextDelta(from event: SSEEvent) {
        guard let textDelta = streamTextDelta(from: event) else {
            return
        }
        currentStreamingText += textDelta
    }

    func applyStreamThinkingDelta(from event: SSEEvent) {
        guard let thinkingDelta = streamThinkingDelta(from: event) else {
            return
        }
        currentThinkingText += thinkingDelta
        isThinking = true
    }

    func applyStreamToolCallUpdate(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: StreamToolCallPayload.self) else {
            return
        }
        activeToolCalls.removeAll { $0.id == payload.toolCall.id }
        activeToolCalls.append(payload.toolCall)
    }

    func applyStreamCitationsUpdate(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: StreamCitationsPayload.self) else {
            return
        }
        liveCitations = payload.citations
    }

    func applyStreamFilePathAnnotationsUpdate(from event: SSEEvent) {
        guard let payload = decodeStreamPayload(event, as: StreamFilePathAnnotationsPayload.self) else {
            return
        }
        liveFilePathAnnotations = payload.filePathAnnotations
    }

    func streamErrorMessage(from event: SSEEvent) -> String {
        if let payload = decodeStreamPayload(event, as: StreamErrorPayload.self),
           let message = payload.message,
           !message.isEmpty {
            return message
        }

        return event.data
    }

    func decodeStreamPayload<Payload: Decodable>(
        _ event: SSEEvent,
        as _: Payload.Type,
        configure: (inout JSONDecoder) -> Void = { _ in }
    ) -> Payload? {
        guard let payloadData = event.data.data(using: .utf8) else {
            return nil
        }

        var decoder = JSONDecoder()
        configure(&decoder)

        do {
            return try decoder.decode(Payload.self, from: payloadData)
        } catch {
            return nil
        }
    }

    func seedThinkingSummaryIfNeeded(_ summary: String) {
        if currentThinkingText.isEmpty {
            currentThinkingText = summary
        }
        isThinking = true
    }

    func replaceThinkingSummary(_ summary: String) {
        guard !summary.isEmpty else {
            return
        }
        currentThinkingText = summary
        isThinking = true
    }

    func refreshConversationAfterStream(conversationServerID: String) async throws {
        try await setCurrentConversation(
            loader.refreshConversationDetail(serverID: conversationServerID)
        )
        syncVisibleState()
        clearLiveSurface()
    }
}
