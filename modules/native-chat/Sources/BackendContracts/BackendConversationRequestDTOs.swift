import Foundation

public struct CreateConversationRequestDTO: Codable, Equatable, Sendable {
    public let title: String
    public let mode: ConversationModeDTO
    public let model: ModelDTO?
    public let reasoningEffort: ReasoningEffortDTO?
    public let agentWorkerReasoningEffort: ReasoningEffortDTO?
    public let serviceTier: ServiceTierDTO?

    public init(
        title: String,
        mode: ConversationModeDTO,
        model: ModelDTO? = nil,
        reasoningEffort: ReasoningEffortDTO? = nil,
        agentWorkerReasoningEffort: ReasoningEffortDTO? = nil,
        serviceTier: ServiceTierDTO? = nil
    ) {
        self.title = title
        self.mode = mode
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.agentWorkerReasoningEffort = agentWorkerReasoningEffort
        self.serviceTier = serviceTier
    }
}

public struct CreateMessageRequestDTO: Codable, Equatable, Sendable {
    public let content: String

    public init(content: String) {
        self.content = content
    }
}

public struct UpdateConversationConfigurationRequestDTO: Codable, Equatable, Sendable {
    public let model: ModelDTO?
    public let reasoningEffort: ReasoningEffortDTO?
    public let agentWorkerReasoningEffort: ReasoningEffortDTO?
    public let serviceTier: ServiceTierDTO?

    public init(
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.agentWorkerReasoningEffort = agentWorkerReasoningEffort
        self.serviceTier = serviceTier
    }
}
