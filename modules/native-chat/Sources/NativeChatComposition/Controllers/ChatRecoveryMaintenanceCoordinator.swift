import Foundation

@MainActor
final class ChatRecoveryMaintenanceCoordinator {
    unowned let state: any (
        ChatConversationSelectionAccess &
            ChatMessageListAccess &
            ChatConfigurationSelectionAccess &
            ChatReplyFeedbackAccess
    )
    unowned let services: any (
        ChatPersistenceAccess &
            ChatTransportServiceAccess
    )
    unowned var conversations: (any ChatConversationManaging)!
    unowned var sessions: (any ChatSessionManaging)!
    unowned var recovery: (any ChatRecoveryManaging)!
    unowned var drafts: (any ChatDraftPreparing)!
    unowned var streaming: (any ChatStreamingRequestStarting)!

    init(
        state: any(
            ChatConversationSelectionAccess &
                ChatMessageListAccess &
                ChatConfigurationSelectionAccess &
                ChatReplyFeedbackAccess
        ),
        services: any(
            ChatPersistenceAccess &
                ChatTransportServiceAccess
        )
    ) {
        self.state = state
        self.services = services
    }
}
