import Foundation

@MainActor
final class ChatRuntimeEngine {
    unowned let viewModel: ChatScreenStore
    let sessionStateStore: SessionProjectionStore
    let streamEventCoordinator: StreamEventCoordinator
    let recoveryCoordinator: RecoveryEffectHandler
    let streamingCoordinator: StreamingEffectHandler

    init(viewModel: ChatScreenStore) {
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
}
