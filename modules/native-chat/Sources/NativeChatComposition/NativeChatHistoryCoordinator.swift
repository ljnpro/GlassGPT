import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import Foundation
import SwiftData

/// Coordinator bridging the history presenter to SwiftData persistence and conversation selection flows.
@MainActor
package final class NativeChatHistoryCoordinator {
    private let modelContext: ModelContext
    private let loadChatConversation: @MainActor (Conversation) -> Void
    private let loadAgentConversation: @MainActor (Conversation) -> Void
    private let handleDeletedConversationSelection: @MainActor (UUID) -> Void
    private let resetVisibleSelections: @MainActor () -> Void
    private let showChatTab: @MainActor () -> Void
    private let showAgentTab: @MainActor () -> Void

    /// Creates a history coordinator with the given SwiftData context, conversation access, and tab switch closure.
    init(
        modelContext: ModelContext,
        loadChatConversation: @escaping @MainActor (Conversation) -> Void,
        loadAgentConversation: @escaping @MainActor (Conversation) -> Void,
        handleDeletedConversationSelection: @escaping @MainActor (UUID) -> Void,
        resetVisibleSelections: @escaping @MainActor () -> Void,
        showChatTab: @escaping @MainActor () -> Void,
        showAgentTab: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.loadChatConversation = loadChatConversation
        self.loadAgentConversation = loadAgentConversation
        self.handleDeletedConversationSelection = handleDeletedConversationSelection
        self.resetVisibleSelections = resetVisibleSelections
        self.showChatTab = showChatTab
        self.showAgentTab = showAgentTab
    }

    /// Constructs a ``HistoryPresenter`` wired to load, select, and delete conversations via SwiftData.
    /// Builds the history presenter backed by SwiftData queries and chat selection callbacks.
    package func makePresenter() -> HistoryPresenter {
        HistoryPresenter(
            conversations: makeHistorySummaries(),
            loadConversations: {
                self.makeHistorySummaries()
            },
            selectConversation: { [self] conversationID in
                if let conversation = fetchConversation(id: conversationID) {
                    switch conversation.mode {
                    case .chat:
                        loadChatConversation(conversation)
                        showChatTab()
                    case .agent:
                        loadAgentConversation(conversation)
                        showAgentTab()
                    }
                }
            },
            deleteConversation: { [self] deletedConversationID in
                if let conversation = fetchConversation(id: deletedConversationID) {
                    modelContext.delete(conversation)
                    saveHistoryChanges(context: "deleteConversation")
                }
                handleDeletedConversationSelection(deletedConversationID)
            },
            deleteAllConversations: { [self] in
                for conversation in fetchAllConversations() {
                    modelContext.delete(conversation)
                }
                saveHistoryChanges(context: "deleteAllConversations")
                resetVisibleSelections()
            }
        )
    }

    private func makeHistorySummaries() -> [HistoryConversationSummary] {
        fetchAllConversations().map(HistoryConversationSummaryBuilder.makeHistorySummary(for:))
    }

    private func fetchConversation(id: UUID) -> Conversation? {
        let predicate = #Predicate<Conversation> { conversation in
            conversation.id == id
        }
        let descriptor = FetchDescriptor<Conversation>(predicate: predicate)
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Loggers.persistence.error("[NativeChatHistoryCoordinator.fetchConversation] \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchAllConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Loggers.persistence.error("[NativeChatHistoryCoordinator.fetchAllConversations] \(error.localizedDescription)")
            return []
        }
    }

    private func saveHistoryChanges(context: String) {
        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[NativeChatHistoryCoordinator.\(context)] \(error.localizedDescription)")
        }
    }
}
