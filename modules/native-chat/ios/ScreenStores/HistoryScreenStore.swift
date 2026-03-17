import Foundation

@Observable
@MainActor
final class HistoryScreenStore {
    var searchText = ""

    private let onSelectConversation: (Conversation) -> Void
    private let onDeleteConversation: (Conversation) -> Void
    private let onDeleteAllConversations: () -> Void

    init(
        onSelectConversation: @escaping (Conversation) -> Void,
        onDeleteConversation: @escaping (Conversation) -> Void,
        onDeleteAllConversations: @escaping () -> Void
    ) {
        self.onSelectConversation = onSelectConversation
        self.onDeleteConversation = onDeleteConversation
        self.onDeleteAllConversations = onDeleteAllConversations
    }

    func selectConversation(_ conversation: Conversation) {
        onSelectConversation(conversation)
    }

    func deleteConversation(_ conversation: Conversation) {
        onDeleteConversation(conversation)
    }

    func deleteAllConversations() {
        onDeleteAllConversations()
    }
}
