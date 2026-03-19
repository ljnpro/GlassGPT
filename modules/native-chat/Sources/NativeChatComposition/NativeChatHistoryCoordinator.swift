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
    private unowned let state: any ChatConversationSelectionAccess
    private let conversations: any ChatConversationManaging
    private let showChatTab: @MainActor () -> Void

    /// Creates a history coordinator with the given SwiftData context, conversation access, and tab switch closure.
    init(
        modelContext: ModelContext,
        state: any ChatConversationSelectionAccess,
        conversations: any ChatConversationManaging,
        showChatTab: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.state = state
        self.conversations = conversations
        self.showChatTab = showChatTab
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
                    conversations.loadConversation(conversation)
                    showChatTab()
                }
            },
            deleteConversation: { [self] deletedConversationID in
                if let conversation = fetchConversation(id: deletedConversationID) {
                    modelContext.delete(conversation)
                    saveHistoryChanges(context: "deleteConversation")
                }
                if state.currentConversation?.id == deletedConversationID {
                    conversations.startNewChat()
                }
            },
            deleteAllConversations: { [self] in
                for conversation in fetchAllConversations() {
                    modelContext.delete(conversation)
                }
                saveHistoryChanges(context: "deleteAllConversations")
                conversations.startNewChat()
            }
        )
    }

    private func makeHistorySummaries() -> [HistoryConversationSummary] {
        fetchAllConversations().map(makeHistorySummary(for:))
    }

    private func makeHistorySummary(for conversation: Conversation) -> HistoryConversationSummary {
        HistoryConversationSummary(
            id: conversation.id,
            title: conversation.title,
            preview: historyPreview(for: conversation),
            updatedAt: conversation.updatedAt,
            modelDisplayName: ModelType(rawValue: conversation.model)?.displayName ?? conversation.model
        )
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

    private func historyPreview(for conversation: Conversation) -> String {
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

    private func saveHistoryChanges(context: String) {
        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[NativeChatHistoryCoordinator.\(context)] \(error.localizedDescription)")
        }
    }
}
