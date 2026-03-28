import ChatDomain
import Foundation
import Observation

/// View model representing a single row in the conversation history list.
public struct HistoryConversationRow: Equatable, Identifiable, Sendable {
    /// The conversation's stable server identifier.
    public let id: String
    /// The mode associated with the conversation.
    public let mode: ConversationMode
    /// The conversation's display title.
    public let title: String
    /// A short preview of the most recent message.
    public let preview: String
    /// Timestamp of the last update.
    public let updatedAt: Date
    /// Human-readable name of the model used.
    public let modelDisplayName: String

    /// Creates a history row.
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

/// Observable presenter that drives the conversation history view.
///
/// All properties and methods are `@MainActor`-isolated.
@Observable
@MainActor
public final class HistoryPresenter {
    /// The current search filter text entered by the user.
    public var searchText = ""
    /// All loaded conversation rows, ordered by most recently updated.
    public private(set) var conversations: [HistoryConversationRow]
    private let loadConversationsHandler: () -> [HistoryConversationSummary]
    private let selectConversationHandler: (String, ConversationMode) -> Void
    private let isSignedInHandler: () -> Bool
    private let openSettingsHandler: () -> Void

    /// Creates a history presenter with initial data and handler closures.
    public init(
        conversations: [HistoryConversationSummary] = [],
        loadConversations: @escaping () -> [HistoryConversationSummary],
        selectConversation: @escaping (String, ConversationMode) -> Void,
        isSignedIn: @escaping () -> Bool = { true },
        openSettings: @escaping () -> Void = {}
    ) {
        self.conversations = conversations.map(Self.makeRow)
        loadConversationsHandler = loadConversations
        selectConversationHandler = selectConversation
        isSignedInHandler = isSignedIn
        openSettingsHandler = openSettings
    }

    public var isSignedIn: Bool {
        isSignedInHandler()
    }

    /// Conversations filtered by ``searchText``. Returns all conversations when the search is empty.
    public var filteredConversations: [HistoryConversationRow] {
        guard !searchText.isEmpty else {
            return conversations
        }

        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Reloads the conversation list from the data source.
    public func refresh() {
        conversations = loadConversationsHandler().map(Self.makeRow)
    }

    /// Notifies the handler that the user selected a conversation.
    public func selectConversation(id: String) {
        guard let conversation = conversations.first(where: { $0.id == id }) else {
            return
        }
        selectConversationHandler(conversation.id, conversation.mode)
    }

    /// Opens the Settings surface so account and sync actions are reachable from signed-out history states.
    public func openSettings() {
        openSettingsHandler()
    }

    private static func makeRow(from summary: HistoryConversationSummary) -> HistoryConversationRow {
        HistoryConversationRow(
            id: summary.id,
            mode: summary.mode,
            title: summary.title,
            preview: summary.preview,
            updatedAt: summary.updatedAt,
            modelDisplayName: summary.modelDisplayName
        )
    }
}
