import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension SessionVisibilityCoordinator {
    static func canApplyVisibleState(
        targetSession: ReplySession,
        visibleMessageID: UUID?,
        currentConversationID: UUID?,
        registeredSession: ReplySession?
    ) -> Bool {
        guard visibleMessageID == targetSession.messageID,
              currentConversationID == targetSession.conversationID,
              registeredSession === targetSession
        else {
            return false
        }

        return true
    }

    static func liveDraftMessageID(
        visibleMessageID: UUID?,
        messages: [Message]
    ) -> UUID? {
        guard let visibleMessageID,
              messages.contains(where: { $0.id == visibleMessageID })
        else {
            return nil
        }

        return visibleMessageID
    }

    static func shouldShowDetachedStreamingBubble(
        isStreaming: Bool,
        liveDraftMessageID: UUID?
    ) -> Bool {
        isStreaming && liveDraftMessageID == nil
    }

    static func placeholderToolCalls(from toolCalls: [ToolCallInfo]) -> [ToolCallInfo] {
        toolCalls.map { toolCall in
            guard toolCall.status != .completed else {
                return toolCall
            }

            return ToolCallInfo(
                id: toolCall.id,
                type: toolCall.type,
                status: .completed,
                code: toolCall.code,
                results: toolCall.results,
                queries: toolCall.queries
            )
        }
    }
}
