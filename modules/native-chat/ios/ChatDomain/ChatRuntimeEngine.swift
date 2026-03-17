import Foundation

@MainActor
final class ChatRuntimeEngine {
    unowned let viewModel: any ChatRuntimeScreenStore
    let storeActor = NativeChatStoreActor()
    let sessionStateStore: SessionProjectionStore
    let streamEventCoordinator: StreamEventCoordinator
    let recoveryCoordinator: RecoveryEffectHandler
    let streamingCoordinator: StreamingEffectHandler

    init(viewModel: any ChatRuntimeScreenStore) {
        self.viewModel = viewModel
        let sessionStateStore = SessionProjectionStore(viewModel: viewModel)
        let streamEventCoordinator = StreamEventCoordinator(viewModel: viewModel)
        let recoveryCoordinator = RecoveryEffectHandler(viewModel: viewModel)
        let streamingCoordinator = StreamingEffectHandler(
            viewModel: viewModel,
            recoveryCoordinator: recoveryCoordinator
        )
        self.sessionStateStore = sessionStateStore
        self.streamEventCoordinator = streamEventCoordinator
        self.recoveryCoordinator = recoveryCoordinator
        self.streamingCoordinator = streamingCoordinator
    }

    func applyVisibleProjection(
        _ projection: ChatVisibleProjection,
        visibleMessageID: UUID?
    ) {
        Task {
            _ = await storeActor.send(
                .applyVisibleProjection(
                    visibleMessageID: visibleMessageID,
                    projection: projection
                )
            )
        }
    }

    func setConversationProjection(_ conversationID: UUID?) {
        Task {
            _ = await storeActor.send(.setConversation(conversationID))
        }
    }
}
