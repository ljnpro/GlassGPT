import Foundation

@MainActor
final class ConversationRuntime {
    unowned let viewModel: ChatViewModel
    let sessionStateStore: SessionStateStore
    let streamEventCoordinator: StreamEventCoordinator
    let recoveryCoordinator: RecoveryCoordinator
    let streamingCoordinator: StreamingCoordinator

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        let sessionStateStore = SessionStateStore(viewModel: viewModel)
        let streamEventCoordinator = StreamEventCoordinator(viewModel: viewModel)
        let recoveryCoordinator = RecoveryCoordinator(viewModel: viewModel)
        let streamingCoordinator = StreamingCoordinator(
            viewModel: viewModel,
            recoveryCoordinator: recoveryCoordinator
        )
        self.sessionStateStore = sessionStateStore
        self.streamEventCoordinator = streamEventCoordinator
        self.recoveryCoordinator = recoveryCoordinator
        self.streamingCoordinator = streamingCoordinator
    }
}
