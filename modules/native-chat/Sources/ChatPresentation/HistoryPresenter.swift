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
    private let controller: HistorySceneController

    public init(
        conversations: [HistoryConversationSummary] = [],
        controller: HistorySceneController
    ) {
        self.conversations = conversations.map(Self.makeRow)
        self.controller = controller
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
        conversations = controller.loadConversations().map(Self.makeRow)
    }

    public func selectConversation(id: UUID) {
        controller.selectConversation(id: id)
    }

    public func deleteConversation(id: UUID) {
        controller.deleteConversation(id: id)
        refresh()
    }

    public func deleteAllConversations() {
        controller.deleteAllConversations()
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
