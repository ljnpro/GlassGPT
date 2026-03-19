import Foundation

@MainActor
final class ChatRecoveryCoordinator {
    unowned let state: any (
        ChatConversationSelectionAccess &
            ChatStreamingProjectionAccess &
            ChatReplyFeedbackAccess
    )
    unowned let services: any (
        ChatPersistenceAccess &
            ChatTransportServiceAccess &
            ChatGeneratedFileServiceAccess &
            ChatRuntimeRegistryAccess
    )
    unowned var conversations: (any ChatConversationManaging)!
    unowned var sessions: (any ChatSessionManaging)!
    unowned var files: (any ChatFileInteractionManaging)!
    unowned var streaming: (any ChatStreamingRequestStarting)!
    let resultApplier: ChatRecoveryResultApplier

    init(
        state: any(
            ChatConversationSelectionAccess &
                ChatStreamingProjectionAccess &
                ChatReplyFeedbackAccess
        ),
        services: any(
            ChatPersistenceAccess &
                ChatTransportServiceAccess &
                ChatGeneratedFileServiceAccess &
                ChatRuntimeRegistryAccess
        )
    ) {
        self.state = state
        self.services = services
        resultApplier = ChatRecoveryResultApplier(
            state: state,
            services: services
        )
    }
}
