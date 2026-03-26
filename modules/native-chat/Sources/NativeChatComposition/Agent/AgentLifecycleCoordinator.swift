import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import UIKit

@MainActor
final class AgentLifecycleCoordinator {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func setupLifecycleObservers() {
        state.backgroundTaskCoordinator.startObservingLifecycle { [weak self] in
            self?.handleEnterBackground()
        } onDidEnterBackground: { [weak self] in
            self?.handleDidEnterBackground()
        } onDidBecomeActive: { [weak self] in
            self?.handleReturnToForeground()
        }
    }

    func handleLaunchBootstrap() async {
        guard state.didCompleteLaunchBootstrap else { return }

        endBackgroundTask()
        await bootstrapPersistedRunsIfNeeded()
    }

    func handleSurfaceAppearance() {
        maybeRecoverVisibleConversationIfNeeded()
    }

    func handleEnterBackground() {
        for execution in state.sessionRegistry.allExecutions {
            execution.markEnteredBackground()
        }
        persistAllExecutions()
        let backgroundEligibleExecutions = state.sessionRegistry.allExecutions
            .filter(\.snapshot.runConfiguration.backgroundModeEnabled)
        guard !backgroundEligibleExecutions.isEmpty else { return }

        state.backgroundTaskCoordinator.beginLongRunningTask(named: "AgentProcess") { [weak self] in
            guard let self else { return }
            for execution in backgroundEligibleExecutions {
                execution.markNeedsForegroundResume()
            }
            persistExecutions(backgroundEligibleExecutions)
            endBackgroundTask()
        }
    }

    func handleDidEnterBackground() {
        persistAllExecutions()
    }

    func handleReturnToForeground() {
        guard state.didCompleteLaunchBootstrap else { return }

        endBackgroundTask()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await resumeForegroundEligibleExecutionsIfNeeded()
            maybeRecoverVisibleConversationIfNeeded()
        }
    }

    func endBackgroundTask() {
        state.backgroundTaskCoordinator.endBackgroundTask()
    }

    private func persistAllExecutions() {
        persistExecutions(state.sessionRegistry.allExecutions)
    }

    private func persistExecutions(_ executions: [AgentExecutionState]) {
        for execution in executions {
            let conversation: Conversation?
            do {
                conversation = try state.conversationRepository.fetchConversation(id: execution.conversationID)
            } catch {
                continue
            }
            guard let conversation else { continue }
            state.runCoordinator.persistSnapshot(execution, in: conversation)
        }
    }

    private func bootstrapPersistedRunsIfNeeded() async {
        let conversations: [Conversation]
        do {
            conversations = try state.conversationRepository.fetchConversationsWithIncompleteDrafts(mode: .agent)
        } catch {
            Loggers.persistence.error("[AgentLifecycleCoordinator.bootstrapPersistedRunsIfNeeded] \(error.localizedDescription)")
            return
        }

        for conversation in conversations {
            if let execution = state.sessionRegistry.execution(for: conversation.id) {
                switch state.runCoordinator.resumeReplacementDisposition(for: execution, in: conversation) {
                case .keep:
                    continue
                case .replaceAndPersistExecutionSnapshot:
                    state.runCoordinator.persistSnapshot(execution, in: conversation)
                    state.sessionRegistry.removeExecution(for: conversation.id)
                case .replaceUsingPersistedRecoverableState:
                    state.sessionRegistry.removeExecution(for: conversation.id)
                }
            }

            let snapshot = conversation.agentConversationState?.activeRun
                ?? conversation.messages
                .last(where: { $0.role == .assistant && !$0.isComplete })
                .map { draft in
                    state.runCoordinator.resumableSnapshot(in: conversation, draft: draft)
                }

            guard let snapshot else {
                continue
            }

            if conversation.id == state.currentConversation?.id {
                state.conversationCoordinator.restoreDraftIfNeeded(
                    from: conversation,
                    autoResume: false,
                    showRetryBannerWhenDormant: false
                )
            }

            guard snapshot.phase.supportsAutomaticResume else {
                continue
            }

            await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
        }
    }

    private func maybeRecoverVisibleConversationIfNeeded() {
        guard state.didCompleteLaunchBootstrap,
              let conversation = state.currentConversation,
              state.sessionRegistry.isVisible(conversation.id)
        else {
            return
        }

        if let execution = state.sessionRegistry.execution(for: conversation.id) {
            switch state.runCoordinator.resumeReplacementDisposition(for: execution, in: conversation) {
            case .keep:
                state.runCoordinator.syncVisibleStateIfNeeded(execution, in: conversation)
            case .replaceAndPersistExecutionSnapshot, .replaceUsingPersistedRecoverableState:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
                }
            }
            return
        }

        guard conversation.messages.contains(where: { $0.role == .assistant && !$0.isComplete }) else {
            return
        }

        state.conversationCoordinator.restoreDraftIfNeeded(
            from: conversation,
            autoResume: true,
            showRetryBannerWhenDormant: true
        )
    }

    private func resumeForegroundEligibleExecutionsIfNeeded() async {
        var persistedConversationIDs: [UUID]
        do {
            persistedConversationIDs = try state.conversationRepository
                .fetchConversationsWithIncompleteDrafts(mode: .agent)
                .map(\.id)
        } catch {
            Loggers.persistence.error(
                "[AgentLifecycleCoordinator.resumeForegroundEligibleExecutionsIfNeeded] \(error.localizedDescription)"
            )
            persistedConversationIDs = []
        }

        let executionConversationIDs = state.sessionRegistry.allExecutions.map(\.conversationID)
        let conversationIDs = Array(Set(executionConversationIDs + persistedConversationIDs))

        for conversationID in conversationIDs {
            let conversation: Conversation?
            do {
                conversation = try state.conversationRepository.fetchConversation(id: conversationID)
            } catch {
                continue
            }
            guard let conversation else { continue }
            if let execution = state.sessionRegistry.execution(for: conversationID) {
                let disposition = state.runCoordinator.resumeReplacementDisposition(for: execution, in: conversation)
                if disposition == .keep {
                    continue
                }
            }
            await state.runCoordinator.resumePersistedRunIfNeeded(conversation)
        }
    }
}
