import Foundation
import UIKit

@MainActor
extension ChatScreenStore {

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
