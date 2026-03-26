import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentConversationCoordinator {
    func loadDefaultsFromSettings() {
        applyConversationConfiguration(
            state.settingsStore.defaultAgentConversationConfiguration,
            persist: false
        )
    }

    func applyConversationConfiguration(
        _ configuration: AgentConversationConfiguration,
        persist: Bool = true
    ) {
        state.leaderReasoningEffort = configuration.leaderReasoningEffort
        state.workerReasoningEffort = configuration.workerReasoningEffort
        state.backgroundModeEnabled = configuration.backgroundModeEnabled
        state.serviceTier = configuration.serviceTier

        guard persist, let conversation = state.currentConversation else { return }

        var agentState = conversation.agentConversationState ?? AgentConversationState()
        agentState.configuration = configuration
        agentState.updatedAt = .now
        conversation.agentConversationState = agentState
        conversation.reasoningEffort = configuration.leaderReasoningEffort.rawValue
        conversation.backgroundModeEnabled = configuration.backgroundModeEnabled
        conversation.serviceTierRawValue = configuration.serviceTier.rawValue
        conversation.updatedAt = .now
        _ = saveContext("applyConversationConfiguration")
    }

    var currentConversationConfiguration: AgentConversationConfiguration {
        AgentConversationConfiguration(
            leaderReasoningEffort: state.leaderReasoningEffort,
            workerReasoningEffort: state.workerReasoningEffort,
            backgroundModeEnabled: state.backgroundModeEnabled,
            serviceTier: state.serviceTier
        )
    }

    func resolvedConfiguration(for conversation: Conversation) -> AgentConversationConfiguration {
        if let configuration = conversation.agentConversationState?.configuration {
            return configuration
        }

        return AgentConversationConfiguration(
            leaderReasoningEffort: ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high,
            workerReasoningEffort: .low,
            backgroundModeEnabled: conversation.backgroundModeEnabled,
            serviceTier: ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
        )
    }

    func ensureConversation() -> Conversation {
        if let conversation = state.currentConversation {
            return conversation
        }

        let configuration = currentConversationConfiguration
        let conversation = Conversation(
            modeRawValue: ConversationMode.agent.rawValue,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: configuration.leaderReasoningEffort.rawValue,
            backgroundModeEnabled: configuration.backgroundModeEnabled,
            serviceTierRawValue: configuration.serviceTier.rawValue
        )
        conversation.mode = .agent
        conversation.agentConversationState = AgentConversationState(
            configuration: configuration
        )
        state.modelContext.insert(conversation)
        state.currentConversation = conversation
        return conversation
    }
}
