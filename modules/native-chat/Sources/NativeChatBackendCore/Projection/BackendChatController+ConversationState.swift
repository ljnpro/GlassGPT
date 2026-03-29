import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import Foundation

@MainActor
extension BackendChatController: BackendConversationConfigurationState {
    package var configurationModelForSync: ModelType? {
        selectedModel
    }

    package var configurationReasoningEffortForSync: ReasoningEffort {
        reasoningEffort
    }

    package var configurationWorkerReasoningEffortForSync: ReasoningEffort? {
        nil
    }

    /// Hydrates visible chat configuration from persisted conversation state.
    package func applyPersistedConfiguration(from conversation: Conversation) {
        selectedModel = ModelType(rawValue: conversation.model) ?? settingsStore.defaultModel
        reasoningEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? selectedModel.defaultEffort
        serviceTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
    }

    /// Writes the current chat configuration back into the persisted conversation record.
    package func updateStoredConversationConfiguration(_ conversation: Conversation) {
        conversation.model = selectedModel.rawValue
        conversation.reasoningEffort = reasoningEffort.rawValue
        conversation.serviceTierRawValue = serviceTier.rawValue
    }
}

@MainActor
package extension BackendChatController {
    func applyConversationConfiguration(_ configuration: ConversationConfiguration) {
        selectedModel = configuration.model
        reasoningEffort = configuration.reasoningEffort
        serviceTier = configuration.serviceTier
        persistVisibleConfiguration()
    }

    func syncMessages() {
        syncVisibleState()
    }
}
