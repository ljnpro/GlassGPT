import Foundation

/// Request body for creating a new conversation on the backend.
public struct CreateConversationRequestDTO: Codable, Equatable, Sendable {
    public let title: String
    public let mode: ConversationModeDTO
    public let model: ModelDTO?
    public let reasoningEffort: ReasoningEffortDTO?
    public let agentWorkerReasoningEffort: ReasoningEffortDTO?
    public let serviceTier: ServiceTierDTO?

    /// Creates a conversation creation request with the given parameters.
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

/// Request body for sending a new message in a conversation.
public struct CreateMessageRequestDTO: Codable, Equatable, Sendable {
    public let content: String
    public let fileIds: [String]?
    public let imageBase64: String?

    /// Creates a message request with text content and optional attachments.
    public init(content: String, fileIds: [String]? = nil, imageBase64: String? = nil) {
        self.content = content
        self.fileIds = fileIds
        self.imageBase64 = imageBase64
    }
}

/// Request body for updating a conversation's model and reasoning settings.
public struct UpdateConversationConfigurationRequestDTO: Codable, Equatable, Sendable {
    public let model: ModelDTO?
    public let reasoningEffort: ReasoningEffortDTO?
    public let agentWorkerReasoningEffort: ReasoningEffortDTO?
    public let serviceTier: ServiceTierDTO?

    /// Creates a configuration update request.
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
