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
