import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import Foundation

@MainActor
extension BackendAgentController: BackendConversationConfigurationState {
    package var configurationModelForSync: ModelType? {
        nil
    }

    package var configurationReasoningEffortForSync: ReasoningEffort {
        leaderReasoningEffort
    }

    package var configurationWorkerReasoningEffortForSync: ReasoningEffort? {
        workerReasoningEffort
    }

    /// Hydrates visible agent configuration from persisted conversation state.
    package func applyPersistedConfiguration(from conversation: Conversation) {
        leaderReasoningEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        workerReasoningEffort = conversation.agentWorkerReasoningEffort ?? .low
        serviceTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
    }

    /// Writes the current agent configuration back into the persisted conversation record.
    package func updateStoredConversationConfiguration(_ conversation: Conversation) {
        conversation.reasoningEffort = leaderReasoningEffort.rawValue
        conversation.agentWorkerReasoningEffortRawValue = workerReasoningEffort.rawValue
        conversation.serviceTierRawValue = serviceTier.rawValue
    }
}

@MainActor
package extension BackendAgentController {
    func applyConfiguration(_ configuration: AgentConversationConfiguration) {
        leaderReasoningEffort = configuration.leaderReasoningEffort
        workerReasoningEffort = configuration.workerReasoningEffort
        serviceTier = configuration.serviceTier
        persistVisibleConfiguration()
    }

    func applyRestoredRunSummary(_ run: RunSummaryDTO) {
        lastRunSummary = run
        processSnapshot = BackendConversationSupport.processSnapshot(
            for: run,
            progressLabel: run.visibleSummary
        )
    }
}
