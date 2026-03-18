import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import Foundation
import SwiftData

@MainActor
final class NativeChatHistoryCoordinator {
    private let modelContext: ModelContext
    private let chatController: ChatController
    private let showChatTab: @MainActor () -> Void

    init(
        modelContext: ModelContext,
        chatController: ChatController,
        showChatTab: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.chatController = chatController
        self.showChatTab = showChatTab
    }

    func makePresenter() -> HistoryPresenter {
        let modelContext = self.modelContext
        let chatController = self.chatController
        let showChatTab = self.showChatTab

        func fetchConversation(id: UUID) -> Conversation? {
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

        func fetchAllConversations() -> [Conversation] {
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

        return HistoryPresenter(
            conversations: fetchAllConversations().map { conversation in
                HistoryConversationSummary(
                    id: conversation.id,
                    title: conversation.title,
                    preview: self.historyPreview(for: conversation),
                    updatedAt: conversation.updatedAt,
                    modelDisplayName: ModelType(rawValue: conversation.model)?.displayName ?? conversation.model
                )
            },
            loadConversations: {
                fetchAllConversations().map { conversation in
                    HistoryConversationSummary(
                        id: conversation.id,
                        title: conversation.title,
                        preview: self.historyPreview(for: conversation),
                        updatedAt: conversation.updatedAt,
                        modelDisplayName: ModelType(rawValue: conversation.model)?.displayName ?? conversation.model
                    )
                }
            },
            selectConversation: { conversationID in
                if let conversation = fetchConversation(id: conversationID) {
                    chatController.conversationCoordinator.loadConversation(conversation)
                    showChatTab()
                }
            },
            deleteConversation: { deletedConversationID in
                if let conversation = fetchConversation(id: deletedConversationID) {
                    modelContext.delete(conversation)
                    self.saveHistoryChanges(context: "deleteConversation")
                }
                if chatController.currentConversation?.id == deletedConversationID {
                    chatController.conversationCoordinator.startNewChat()
                }
            },
            deleteAllConversations: {
                for conversation in fetchAllConversations() {
                    modelContext.delete(conversation)
                }
                self.saveHistoryChanges(context: "deleteAllConversations")
                chatController.conversationCoordinator.startNewChat()
            }
        )
    }

    private func historyPreview(for conversation: Conversation) -> String {
        let sortedMessages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        guard let lastMessage = sortedMessages.last else {
            return "No messages"
        }

        let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return trimmedContent.prefix(100).description
        }

        if lastMessage.role == .assistant && !lastMessage.isComplete {
            if let thinking = lastMessage.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                return thinking.prefix(100).description
            }

            return "Generating..."
        }

        return "No messages"
    }

    private func saveHistoryChanges(context: String) {
        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[NativeChatHistoryCoordinator.\(context)] \(error.localizedDescription)")
        }
    }
}
