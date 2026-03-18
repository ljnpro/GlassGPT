import ChatPersistenceSwiftData
import ChatDomain
import ChatPersistenceCore
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
extension ChatController {

    // MARK: - Lifecycle Observers

    func setupLifecycleObservers() {
        backgroundTaskCoordinator.startObservingLifecycle { [weak self] in
            self?.handleEnterBackground()
        } onDidEnterBackground: { [weak self] in
            self?.handleDidEnterBackground()
        } onDidBecomeActive: { [weak self] in
            self?.handleReturnToForeground()
        }
    }

    func handleEnterBackground() {
        if !sessionRegistry.allSessions.isEmpty {
            for session in sessionRegistry.allSessions {
                saveSessionNow(session)
            }

            backgroundTaskCoordinator.beginLongRunningTask(named: "StreamCompletion") { [weak self] in
                guard let self else { return }
                self.suspendActiveSessionsForAppBackground()
                self.endBackgroundTask()
            }
        }

        if let conversation = currentConversation,
           conversation.title == "New Chat",
           messages.count >= 2 {
            backgroundTaskCoordinator.runTransientTask(named: "TitleGeneration") { [weak self] in
                guard let self else { return }
                await self.generateTitle()
            }
        }
    }

    func handleDidEnterBackground() {
        guard !sessionRegistry.allSessions.isEmpty else { return }
        for session in sessionRegistry.allSessions {
            saveSessionNow(session)
        }
    }

    func handleReturnToForeground() {
        guard didCompleteLaunchBootstrap else { return }

        endBackgroundTask()
        refreshVisibleBindingForCurrentConversation()

        Task { @MainActor in
            await self.recoverIncompleteMessagesInCurrentConversation()
            await self.recoverIncompleteMessages()
        }
    }

    func endBackgroundTask() {
        backgroundTaskCoordinator.endBackgroundTask()
    }

    // MARK: - Persistence Helpers

    @discardableResult
    func saveContext(
        reportingUserError userError: String? = nil,
        logContext: String
    ) -> Bool {
        do {
            try conversationRepository.save()
            return true
        } catch {
            if let userError {
                errorMessage = userError
            }
            Loggers.persistence.error("[\(logContext)] \(error.localizedDescription)")
            return false
        }
    }

    func saveContextIfPossible(_ logContext: String) {
        _ = saveContext(logContext: logContext)
    }

    func loadDefaultsFromSettings() {
        let defaults = settingsStore.defaultConversationConfiguration
        selectedModel = defaults.model
        reasoningEffort = defaults.reasoningEffort
        backgroundModeEnabled = defaults.backgroundModeEnabled
        serviceTier = defaults.serviceTier

        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }
    }

    func applyConversationConfiguration(from conversation: Conversation) {
        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard

        isApplyingStoredConversationConfiguration = true
        selectedModel = model
        reasoningEffort = resolvedEffort
        backgroundModeEnabled = conversation.backgroundModeEnabled
        serviceTier = resolvedTier
        isApplyingStoredConversationConfiguration = false
    }
}
