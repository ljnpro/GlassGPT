import Foundation

/// Lightweight summary of a conversation for display in the history list.
public struct HistoryConversationSummary: Equatable, Identifiable, Sendable {
    /// The conversation's unique identifier.
    public let id: UUID
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
        id: UUID,
        title: String,
        preview: String,
        updatedAt: Date,
        modelDisplayName: String
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
        self.modelDisplayName = modelDisplayName
    }
}
