import Foundation
import UIKit

@MainActor
final class BackgroundTaskCoordinator: NSObject {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let notificationCenter: NotificationCenter
    private var onWillResignActive: (@MainActor () -> Void)?
    private var onDidEnterBackground: (@MainActor () -> Void)?
    private var onDidBecomeActive: (@MainActor () -> Void)?
    private var isObserving = false

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    deinit {
        if isObserving {
            notificationCenter.removeObserver(self)
        }
    }

    func startObservingLifecycle(
        onWillResignActive: @escaping @MainActor () -> Void,
        onDidEnterBackground: @escaping @MainActor () -> Void,
        onDidBecomeActive: @escaping @MainActor () -> Void
    ) {
        self.onWillResignActive = onWillResignActive
        self.onDidEnterBackground = onDidEnterBackground
        self.onDidBecomeActive = onDidBecomeActive

        guard !isObserving else { return }
        isObserving = true

        notificationCenter.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func beginLongRunningTask(named name: String, expiration: @escaping @MainActor () -> Void) {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in
                expiration()
            }
        }
    }

    func runTransientTask(named name: String, operation: @escaping @MainActor () async -> Void) {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: name)
        Task { @MainActor in
            await operation()
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
    }

    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    @objc private func handleWillResignActive() {
        onWillResignActive?()
    }

    @objc private func handleDidEnterBackground() {
        onDidEnterBackground?()
    }

    @objc private func handleDidBecomeActive() {
        onDidBecomeActive?()
    }
}
