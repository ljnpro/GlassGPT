import ChatDomain
import ChatProjectionPersistence

/// Shared configuration persistence and backend-sync behavior for backend conversation controllers.
@MainActor
package protocol BackendConversationConfigurationState: BackendConversationProjectionController {
    var serviceTier: ServiceTier { get set }
    var configurationModelForSync: ModelType? { get }
    var configurationReasoningEffortForSync: ReasoningEffort { get }
    var configurationWorkerReasoningEffortForSync: ReasoningEffort? { get }

    func applyPersistedConfiguration(from conversation: Conversation)
    func updateStoredConversationConfiguration(_ conversation: Conversation)
}

@MainActor
package extension BackendConversationConfigurationState {
    /// Persists the controller's visible configuration into the current conversation record.
    func persistVisibleConfiguration() {
        guard let currentConversationRecord else {
            return
        }
        updateStoredConversationConfiguration(currentConversationRecord)
    }

    /// Pushes the current visible configuration to the backend and returns the updated record.
    func requestUpdatedConversationConfiguration(serverID: String) async throws -> Conversation {
        try await loader.updateConversationConfiguration(
            serverID: serverID,
            mode: conversationMode,
            model: configurationModelForSync,
            reasoningEffort: configurationReasoningEffortForSync,
            agentWorkerReasoningEffort: configurationWorkerReasoningEffortForSync,
            serviceTier: serviceTier
        )
    }

    /// Rehydrates visible configuration from the current persisted conversation record.
    func hydrateConfigurationFromConversation() {
        guard let currentConversationRecord else {
            return
        }
        applyPersistedConfiguration(from: currentConversationRecord)
    }

    /// Ensures a persisted conversation exists before submitting or syncing configuration.
    func ensureConversation() async throws -> Conversation {
        if let currentConversationRecordValue {
            return currentConversationRecordValue
        }

        let createdConversation = try await loader.createConversation(
            title: BackendConversationSupport.defaultConversationTitle(for: conversationMode),
            mode: conversationMode,
            model: configurationModelForSync,
            reasoningEffort: configurationReasoningEffortForSync,
            agentWorkerReasoningEffort: configurationWorkerReasoningEffortForSync,
            serviceTier: serviceTier
        )
        setCurrentConversation(createdConversation)
        hydrateConfigurationFromConversation()
        syncVisibleState()
        return createdConversation
    }
}
