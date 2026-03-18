import ChatApplication
import Foundation
import Observation

public struct HistoryConversationRow: Equatable, Identifiable, Sendable {
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

@Observable
@MainActor
public final class HistoryPresenter {
    public var searchText = ""
    public private(set) var conversations: [HistoryConversationRow]
    private let loadConversationsHandler: () -> [HistoryConversationSummary]
    private let selectConversationHandler: (UUID) -> Void
    private let deleteConversationHandler: (UUID) -> Void
    private let deleteAllConversationsHandler: () -> Void

    public init(
        conversations: [HistoryConversationSummary] = [],
        loadConversations: @escaping () -> [HistoryConversationSummary],
        selectConversation: @escaping (UUID) -> Void,
        deleteConversation: @escaping (UUID) -> Void,
        deleteAllConversations: @escaping () -> Void
    ) {
        self.conversations = conversations.map(Self.makeRow)
        self.loadConversationsHandler = loadConversations
        self.selectConversationHandler = selectConversation
        self.deleteConversationHandler = deleteConversation
        self.deleteAllConversationsHandler = deleteAllConversations
    }

    public var filteredConversations: [HistoryConversationRow] {
        guard !searchText.isEmpty else {
            return conversations
        }

        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    public func refresh() {
        conversations = loadConversationsHandler().map(Self.makeRow)
    }

    public func selectConversation(id: UUID) {
        selectConversationHandler(id)
    }

    public func deleteConversation(id: UUID) {
        deleteConversationHandler(id)
        refresh()
    }

    public func deleteAllConversations() {
        deleteAllConversationsHandler()
        refresh()
    }

    private static func makeRow(from summary: HistoryConversationSummary) -> HistoryConversationRow {
        HistoryConversationRow(
            id: summary.id,
            title: summary.title,
            preview: summary.preview,
            updatedAt: summary.updatedAt,
            modelDisplayName: summary.modelDisplayName
        )
    }
}
