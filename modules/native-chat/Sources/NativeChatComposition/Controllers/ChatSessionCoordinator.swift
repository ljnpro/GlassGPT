import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
final class ChatSessionCoordinator {
    unowned let state: any ChatSessionCoordinatorStateAccess
    unowned let services: any ChatSessionCoordinatorServiceAccess
    unowned var conversations: (any ChatConversationManaging)!
    unowned var files: (any ChatFileInteractionManaging)!
    unowned var recovery: (any ChatRecoveryManaging)!

    init(
        state: any ChatSessionCoordinatorStateAccess,
        services: any ChatSessionCoordinatorServiceAccess
    ) {
        self.state = state
        self.services = services
    }

    var currentVisibleSession: ReplySession? {
        services.sessionRegistry.currentVisibleSession
    }

    var visibleSessionMessageID: UUID? {
        services.sessionRegistry.visibleMessageID
    }
}
