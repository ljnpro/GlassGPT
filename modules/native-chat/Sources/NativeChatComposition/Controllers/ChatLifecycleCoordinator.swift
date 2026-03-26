import ChatPersistenceCore
import ChatPersistenceSwiftData
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

@MainActor
final class ChatLifecycleCoordinator {
    unowned let state: any (
        ChatConversationSelectionAccess &
            ChatMessageListAccess &
            ChatBootstrapStateAccess
    )
    unowned let services: any (
        ChatPersistenceAccess &
            ChatTransportServiceAccess &
            ChatBackgroundTaskAccess &
            ChatRuntimeRegistryAccess
    )
    unowned var sessions: (any ChatSessionManaging)!
    unowned var recoveryMaintenance: (any ChatRecoveryMaintenanceManaging)!
    unowned var conversations: (any ChatConversationManaging)!

    init(
        state: any(
            ChatConversationSelectionAccess &
                ChatMessageListAccess &
                ChatBootstrapStateAccess
        ),
        services: any(
            ChatPersistenceAccess &
                ChatTransportServiceAccess &
                ChatBackgroundTaskAccess &
                ChatRuntimeRegistryAccess
        )
    ) {
        self.state = state
        self.services = services
    }

    func setupLifecycleObservers() {
        services.backgroundTaskCoordinator.startObservingLifecycle { [weak self] in
            self?.handleEnterBackground()
        } onDidEnterBackground: { [weak self] in
            self?.handleDidEnterBackground()
        } onDidBecomeActive: { [weak self] in
            self?.handleReturnToForeground()
        }
    }

    func handleEnterBackground() {
        if !services.sessionRegistry.allSessions.isEmpty {
            for session in services.sessionRegistry.allSessions {
                sessions.saveSessionNow(session)
                services.sessionRegistry.execution(for: session.messageID)?.markEnteredBackground()
            }

            services.backgroundTaskCoordinator.beginLongRunningTask(named: "StreamCompletion") { [weak self] in
                guard let self else { return }
                for session in services.sessionRegistry.allSessions {
                    services.sessionRegistry.execution(for: session.messageID)?.markNeedsForegroundResume()
                }
                sessions.suspendActiveSessionsForAppBackground()
                endBackgroundTask()
            }
        }

        if let conversation = state.currentConversation,
           conversation.title == "New Chat",
           state.messages.count >= 2 {
            services.backgroundTaskCoordinator.runTransientTask(named: "TitleGeneration") { [weak self] in
                guard let self else { return }
                await generateTitle()
            }
        }
    }

    func handleDidEnterBackground() {
        guard !services.sessionRegistry.allSessions.isEmpty else { return }
        for session in services.sessionRegistry.allSessions {
            sessions.saveSessionNow(session)
        }
    }

    func handleReturnToForeground() {
        guard state.didCompleteLaunchBootstrap else { return }

        endBackgroundTask()
        sessions.refreshVisibleBindingForCurrentConversation()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await recoveryMaintenance.recoverIncompleteMessagesInCurrentConversation()
            await recoveryMaintenance.recoverIncompleteMessages()
            await recoveryMaintenance.resendOrphanedDrafts()
        }
    }

    func endBackgroundTask() {
        services.backgroundTaskCoordinator.endBackgroundTask()
    }
}
