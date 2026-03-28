import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import Foundation
import SwiftData

/// Coordinator bridging the history presenter to SwiftData persistence and conversation selection flows.
@MainActor
package final class NativeChatHistoryCoordinator {
    private let modelContext: ModelContext
    private let currentAccountID: @MainActor () -> String?
    private let loadChatConversation: @MainActor (String) -> Void
    private let loadAgentConversation: @MainActor (String) -> Void
    private let showChatTab: @MainActor () -> Void
    private let showAgentTab: @MainActor () -> Void
    private let showSettingsTab: @MainActor () -> Void

    /// Creates a history coordinator with the given SwiftData context, conversation access, and tab switch closure.
    init(
        modelContext: ModelContext,
        currentAccountID: @escaping @MainActor () -> String?,
        loadChatConversation: @escaping @MainActor (String) -> Void,
        loadAgentConversation: @escaping @MainActor (String) -> Void,
        showChatTab: @escaping @MainActor () -> Void,
        showAgentTab: @escaping @MainActor () -> Void,
        showSettingsTab: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.currentAccountID = currentAccountID
        self.loadChatConversation = loadChatConversation
        self.loadAgentConversation = loadAgentConversation
        self.showChatTab = showChatTab
        self.showAgentTab = showAgentTab
        self.showSettingsTab = showSettingsTab
    }

    /// Constructs a ``HistoryPresenter`` wired to load, select, and delete conversations via SwiftData.
    /// Builds the history presenter backed by SwiftData queries and chat selection callbacks.
    package func makePresenter() -> HistoryPresenter {
        HistoryPresenter(
            conversations: makeHistorySummaries(),
            loadConversations: {
                self.makeHistorySummaries()
            },
            selectConversation: { [self] conversationID, mode in
                switch mode {
                case .chat:
                    loadChatConversation(conversationID)
                    showChatTab()
                case .agent:
                    loadAgentConversation(conversationID)
                    showAgentTab()
                }
            },
            isSignedIn: { [self] in
                currentAccountID() != nil
            },
            openSettings: { [self] in
                showSettingsTab()
            }
        )
    }

    private func makeHistorySummaries() -> [HistoryConversationSummary] {
        fetchAllConversations().compactMap(HistoryConversationSummaryBuilder.makeHistorySummary(for:))
    }

    private func fetchAllConversations() -> [Conversation] {
        guard let accountID = currentAccountID() else {
            return []
        }
        do {
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conversation in
                    conversation.syncAccountID == accountID
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            Loggers.persistence.error("[NativeChatHistoryCoordinator.fetchAllConversations] \(error.localizedDescription)")
            return []
        }
    }
}
