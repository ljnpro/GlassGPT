import BackendClient
import ChatDomain
import Foundation

private struct DeltaPayload: Decodable {
    let textDelta: String?
}

private struct ThinkingDeltaPayload: Decodable {
    let thinkingDelta: String?
}

private struct StatusPayload: Decodable {
    let visibleSummary: String?
}

private struct StagePayload: Decodable {
    let visibleSummary: String?
}

private struct ToolCallPayload: Decodable {
    let toolCall: ToolCallInfo
}

private struct CitationsPayload: Decodable {
    let citations: [URLCitation]
}

private struct FilePathAnnotationsPayload: Decodable {
    let filePathAnnotations: [FilePathAnnotation]
}

/// Describes whether a chat stream event should continue the active stream loop or terminate it.
package enum ChatStreamOutcome {
    case continueLoop
    case finish
}

@MainActor
package extension BackendChatController {
    func beginChatStream() {
        isStreaming = true
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
    }

    func handleChatStreamEvent(
        _ event: SSEEvent,
        conversationServerID: String
    ) async throws -> ChatStreamOutcome {
        switch event.event {
        case "delta":
            applyChatTextDelta(from: event)
            return .continueLoop
        case "thinking_delta":
            applyChatThinkingDelta(from: event)
            return .continueLoop
        case "thinking_done":
            isThinking = false
            return .continueLoop
        case "tool_call_update":
            applyChatToolCallUpdate(from: event)
            return .continueLoop
        case "citations_update":
            applyChatCitationsUpdate(from: event)
            return .continueLoop
        case "file_path_annotations_update":
            applyChatFilePathAnnotationsUpdate(from: event)
            return .continueLoop
        case "status":
            applyChatStatus(from: event)
            return .continueLoop
        case "stage":
            applyChatStage(from: event)
            return .continueLoop
        case "done":
            try await finalizeChatStream(conversationServerID: conversationServerID)
            return .finish
        case "error":
            errorMessage = event.data
            return .finish
        default:
            return .continueLoop
        }
    }

    func applyChatTextDelta(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: DeltaPayload.self),
              let textDelta = payload.textDelta
        else {
            return
        }
        currentStreamingText += textDelta
    }

    func applyChatThinkingDelta(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: ThinkingDeltaPayload.self),
              let thinkingDelta = payload.thinkingDelta
        else {
            return
        }
        currentThinkingText += thinkingDelta
        isThinking = true
    }

    func applyChatToolCallUpdate(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: ToolCallPayload.self) else {
            return
        }
        activeToolCalls.removeAll { $0.id == payload.toolCall.id }
        activeToolCalls.append(payload.toolCall)
    }

    func applyChatCitationsUpdate(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: CitationsPayload.self) else {
            return
        }
        liveCitations = payload.citations
    }

    func applyChatFilePathAnnotationsUpdate(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: FilePathAnnotationsPayload.self) else {
            return
        }
        liveFilePathAnnotations = payload.filePathAnnotations
    }

    func applyChatStatus(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: StatusPayload.self),
              let summary = payload.visibleSummary
        else {
            return
        }
        if currentThinkingText.isEmpty {
            currentThinkingText = summary
        }
        isThinking = true
    }

    func applyChatStage(from event: SSEEvent) {
        guard let payload = decodeChatPayload(event, as: StagePayload.self),
              let summary = payload.visibleSummary,
              !summary.isEmpty
        else {
            return
        }

        currentThinkingText = summary
        isThinking = true
    }

    func refreshVisibleProjection() async throws {
        try await loader.applyIncrementalSync()
        try await refreshVisibleConversation()
    }

    func finalizeChatStream(conversationServerID: String) async throws {
        try await setCurrentConversation(
            loader.refreshConversationDetail(serverID: conversationServerID)
        )
        syncMessages()
        clearChatLiveSurface()
    }

    func finishChatStreamAfterTermination(
        conversationServerID: String,
        selectionToken: UUID
    ) async {
        do {
            guard visibleSelectionToken == selectionToken else { return }
            try await setCurrentConversation(
                loader.refreshConversationDetail(serverID: conversationServerID)
            )
            syncMessages()
            clearChatLiveSurface()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearChatLiveSurface() {
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isThinking = false
    }

    func decodeChatPayload<Payload: Decodable>(
        _ event: SSEEvent,
        as _: Payload.Type
    ) -> Payload? {
        guard let payloadData = event.data.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Payload.self, from: payloadData)
        } catch {
            return nil
        }
    }
}
