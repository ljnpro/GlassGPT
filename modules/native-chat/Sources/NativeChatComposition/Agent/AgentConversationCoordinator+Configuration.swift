import ChatDomain
import ChatPersistenceSwiftData
import Foundation

extension AgentConversationCoordinator {
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
