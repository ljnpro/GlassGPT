import Foundation

@MainActor
extension ChatController {
    func setupLifecycleObservers() {
        lifecycleCoordinator.setupLifecycleObservers()
    }

    func handleEnterBackground() {
        lifecycleCoordinator.handleEnterBackground()
    }

    func handleDidEnterBackground() {
        lifecycleCoordinator.handleDidEnterBackground()
    }

    func handleReturnToForeground() {
        lifecycleCoordinator.handleReturnToForeground()
    }

    func endBackgroundTask() {
        lifecycleCoordinator.endBackgroundTask()
    }
}
