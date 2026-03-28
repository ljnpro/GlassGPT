import ChatDomain
import Foundation

/// Lightweight summary of a conversation for display in the history list.
public struct HistoryConversationSummary: Equatable, Identifiable, Sendable {
    /// The conversation's stable server identifier.
    public let id: String
    /// The visible mode of the conversation.
    public let mode: ConversationMode
    /// The conversation's title.
    public let title: String
    /// A short preview of the last message content.
    public let preview: String
    /// Timestamp of the most recent update.
    public let updatedAt: Date
    /// Human-readable name of the model used in this conversation.
    public let modelDisplayName: String

    /// Creates a conversation summary.
    public init(
        id: String,
        mode: ConversationMode,
        title: String,
        preview: String,
        updatedAt: Date,
        modelDisplayName: String
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
        self.modelDisplayName = modelDisplayName
    }
}
