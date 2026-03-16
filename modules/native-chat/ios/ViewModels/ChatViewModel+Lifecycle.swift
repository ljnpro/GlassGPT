import Foundation
import UIKit

@MainActor
extension ChatViewModel {

    // MARK: - Lifecycle Observers

    func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleReturnToForeground()
            }
        }
    }

    func handleEnterBackground() {
        if !activeResponseSessions.isEmpty {
            for session in activeResponseSessions.values {
                saveSessionNow(session)
            }

            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StreamCompletion") { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.suspendActiveSessionsForAppBackground()
                    self.endBackgroundTask()
                }
            }
        }

        if let conversation = currentConversation,
           conversation.title == "New Chat",
           messages.count >= 2 {
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "TitleGeneration")
            Task { @MainActor in
                await self.generateTitle()
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        }
    }

    func handleDidEnterBackground() {
        guard !activeResponseSessions.isEmpty else { return }
        suspendActiveSessionsForAppBackground()
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
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
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
