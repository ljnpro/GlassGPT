import Foundation

public struct HistoryConversationSummary: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let preview: String
    public let updatedAt: Date
    public let modelDisplayName: String

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
