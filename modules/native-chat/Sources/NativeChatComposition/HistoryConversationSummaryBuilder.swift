import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import Foundation

enum HistoryConversationSummaryBuilder {
    static func makeHistorySummary(for conversation: Conversation) -> HistoryConversationSummary {
        HistoryConversationSummary(
            id: conversation.id,
            title: conversation.title,
            preview: historyPreview(for: conversation),
            updatedAt: conversation.updatedAt,
            modelDisplayName: conversation.mode == .agent
                ? ConversationMode.agent.displayName
                : (ModelType(rawValue: conversation.model)?.displayName ?? conversation.model)
        )
    }

    private static func historyPreview(for conversation: Conversation) -> String {
        let sortedMessages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        guard let lastMessage = sortedMessages.last else {
            return String(localized: "No messages")
        }

        let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return trimmedContent.prefix(100).description
        }

        if lastMessage.role == .assistant, !lastMessage.isComplete {
            if let thinking = lastMessage.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                return thinking.prefix(100).description
            }

            return String(localized: "Generating...")
        }

        return String(localized: "No messages")
    }
}
