import ChatPresentation
import ChatProjectionPersistence
import Foundation
import SwiftData

/// Factory that assembles the production history presenter from chat-composition collaborators.
@MainActor
package enum NativeChatHistoryPresenterFactory {
    /// Builds the history presenter for the current model context and chat controller.
    package static func makePresenter(
        modelContext: ModelContext,
        currentAccountID: @escaping @MainActor () -> String?,
        loadChatConversation: @escaping @MainActor (String) -> Void,
        loadAgentConversation: @escaping @MainActor (String) -> Void,
        showChatTab: @escaping @MainActor () -> Void,
        showAgentTab: @escaping @MainActor () -> Void,
        showSettingsTab: @escaping @MainActor () -> Void
    ) -> HistoryPresenter {
        NativeChatHistoryCoordinator(
            modelContext: modelContext,
            currentAccountID: currentAccountID,
            loadChatConversation: loadChatConversation,
            loadAgentConversation: loadAgentConversation,
            showChatTab: showChatTab,
            showAgentTab: showAgentTab,
            showSettingsTab: showSettingsTab
        )
        .makePresenter()
    }
}
