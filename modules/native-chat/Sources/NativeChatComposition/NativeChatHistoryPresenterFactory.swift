import ChatPresentation
import SwiftData

/// Factory that assembles the production history presenter from chat-composition collaborators.
@MainActor
package enum NativeChatHistoryPresenterFactory {
    /// Builds the history presenter for the current model context and chat controller.
    package static func makePresenter(
        modelContext: ModelContext,
        chatController: ChatController,
        agentController: AgentController,
        showChatTab: @escaping @MainActor () -> Void,
        showAgentTab: @escaping @MainActor () -> Void
    ) -> HistoryPresenter {
        NativeChatHistoryCoordinator(
            modelContext: modelContext,
            loadChatConversation: { conversation in
                chatController.conversationCoordinator.loadConversation(conversation)
            },
            loadAgentConversation: { conversation in
                agentController.loadConversation(conversation)
            },
            handleDeletedConversationSelection: { deletedConversationID in
                if chatController.currentConversation?.id == deletedConversationID {
                    chatController.conversationCoordinator.startNewChat()
                }
                if agentController.currentConversation?.id == deletedConversationID {
                    agentController.startNewConversation()
                }
            },
            resetVisibleSelections: {
                chatController.conversationCoordinator.startNewChat()
                agentController.startNewConversation()
            },
            showChatTab: showChatTab,
            showAgentTab: showAgentTab
        )
        .makePresenter()
    }
}
