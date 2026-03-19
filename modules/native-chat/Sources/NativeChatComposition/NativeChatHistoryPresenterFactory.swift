import ChatPresentation
import SwiftData

/// Factory that assembles the production history presenter from chat-composition collaborators.
@MainActor
package enum NativeChatHistoryPresenterFactory {
    /// Builds the history presenter for the current model context and chat controller.
    package static func makePresenter(
        modelContext: ModelContext,
        chatController: ChatController,
        showChatTab: @escaping @MainActor () -> Void
    ) -> HistoryPresenter {
        NativeChatHistoryCoordinator(
            modelContext: modelContext,
            state: chatController,
            conversations: chatController.conversationCoordinator,
            showChatTab: showChatTab
        )
        .makePresenter()
    }
}
