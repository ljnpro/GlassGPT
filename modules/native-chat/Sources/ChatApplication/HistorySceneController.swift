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

@MainActor
public final class HistorySceneController {
    private let loadConversationsHandler: () -> [HistoryConversationSummary]
    private let selectConversationHandler: (UUID) -> Void
    private let deleteConversationHandler: (UUID) -> Void
    private let deleteAllConversationsHandler: () -> Void

    public init(
        loadConversations: @escaping () -> [HistoryConversationSummary],
        selectConversation: @escaping (UUID) -> Void,
        deleteConversation: @escaping (UUID) -> Void,
        deleteAllConversations: @escaping () -> Void
    ) {
        self.loadConversationsHandler = loadConversations
        self.selectConversationHandler = selectConversation
        self.deleteConversationHandler = deleteConversation
        self.deleteAllConversationsHandler = deleteAllConversations
    }

    public func loadConversations() -> [HistoryConversationSummary] {
        loadConversationsHandler()
    }

    public func selectConversation(id: UUID) {
        selectConversationHandler(id)
    }

    public func deleteConversation(id: UUID) {
        deleteConversationHandler(id)
    }

    public func deleteAllConversations() {
        deleteAllConversationsHandler()
    }
}
