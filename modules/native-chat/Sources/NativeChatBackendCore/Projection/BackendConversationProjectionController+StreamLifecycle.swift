import ChatDomain
import Foundation

@MainActor
package extension BackendConversationProjectionController {
    func finalizeVisibleRun(conversationServerID: String) async throws {
        try await setCurrentConversation(
            loader.refreshConversationDetail(serverID: conversationServerID)
        )
        syncVisibleState()
    }

    /// Syncs live overlay state (thinking, tool calls, streaming text) from
    /// the latest polled messages so the UI shows progress during active runs.
    /// Without this, the live overlay properties stay empty because no SSE
    /// events populate them in the polling-only architecture.
    func applyLiveOverlayFromPolledMessages() {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }

        // Thinking state
        let hasThinking = !(lastAssistant.thinking?.isEmpty ?? true)
        let hasContent = !lastAssistant.content.isEmpty
        isThinking = hasThinking && !hasContent
        if hasThinking {
            currentThinkingText = lastAssistant.thinking ?? ""
        }
        if hasContent {
            currentStreamingText = lastAssistant.content
        }

        // Tool calls — grace period state machine.
        // With 250ms polling, tool calls often transition to "completed" within
        // a single poll interval. We track when each tool call was first observed
        // and keep it displayed as "in_progress" for a 3-second grace period so
        // the user sees the indicator.
        let now = Date()
        let gracePeriod = toolCallGracePeriodSeconds
        let currentToolCallIDs = Set(lastAssistant.toolCalls.map(\.id))
        toolCallFirstSeen = toolCallFirstSeen.filter { currentToolCallIDs.contains($0.key) }
        for toolCall in lastAssistant.toolCalls {
            if toolCallFirstSeen[toolCall.id] == nil {
                toolCallFirstSeen[toolCall.id] = now
            }
        }
        activeToolCalls = lastAssistant.toolCalls.map { toolCall in
            let firstSeen = toolCallFirstSeen[toolCall.id] ?? now
            let age = now.timeIntervalSince(firstSeen)
            if toolCall.status == .completed, age < gracePeriod {
                return ToolCallInfo(
                    id: toolCall.id,
                    type: toolCall.type,
                    status: .inProgress,
                    code: toolCall.code,
                    results: toolCall.results,
                    queries: toolCall.queries
                )
            }
            return toolCall
        }

        // Citations and file path annotations
        if !lastAssistant.annotations.isEmpty {
            liveCitations = lastAssistant.annotations
        }
        if !lastAssistant.filePathAnnotations.isEmpty {
            liveFilePathAnnotations = lastAssistant.filePathAnnotations
        }
    }

    func toolCallGracePeriodRemaining(now: Date = Date()) -> TimeInterval {
        activeToolCalls
            .compactMap { toolCallFirstSeen[$0.id] }
            .map { max(0, toolCallGracePeriodSeconds - now.timeIntervalSince($0)) }
            .max() ?? 0
    }

    /// When the D1 read replica has not yet replicated the latest content,
    /// the last assistant message may be empty despite the SSE stream having
    /// delivered the full text.  This method patches the visible messages with
    /// the content received over SSE so the user never sees a blank response.
    func applyStreamingFallbackIfNeeded(streamedContent: String, streamedThinking: String) {
        guard !streamedContent.isEmpty else { return }
        guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        let lastMessage = messages[lastIndex]
        guard lastMessage.content.isEmpty || lastMessage.content.count < streamedContent.count else { return }
        messages[lastIndex] = BackendMessageSurface(
            id: lastMessage.id,
            role: lastMessage.role,
            content: streamedContent,
            thinking: (lastMessage.thinking?.isEmpty ?? true) ? streamedThinking : lastMessage.thinking,
            imageData: lastMessage.imageData,
            isComplete: true,
            annotations: lastMessage.annotations,
            toolCalls: lastMessage.toolCalls,
            fileAttachments: lastMessage.fileAttachments,
            filePathAnnotations: lastMessage.filePathAnnotations,
            agentTrace: lastMessage.agentTrace,
            payloadRenderDigest: lastMessage.payloadRenderDigest
        )
    }
}
