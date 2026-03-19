import Foundation

@MainActor
final class ChatStreamingCoordinator {
    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    unowned let state: any (ChatStreamingProjectionAccess & ChatReplyFeedbackAccess)
    unowned let services: any (ChatTransportServiceAccess & ChatBackgroundTaskAccess & ChatRuntimeRegistryAccess)
    unowned var sessions: (any ChatSessionManaging)!
    unowned var conversations: (any ChatConversationManaging)!
    unowned var recovery: (any ChatRecoveryManaging)!

    init(
        state: any(ChatStreamingProjectionAccess & ChatReplyFeedbackAccess),
        services: any(ChatTransportServiceAccess & ChatBackgroundTaskAccess & ChatRuntimeRegistryAccess)
    ) {
        self.state = state
        self.services = services
    }

    func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = sessions.currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }
}
