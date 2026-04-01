import Foundation

/// Whether a conversation operates in chat or agent mode.
public enum ConversationModeDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case chat
    case agent
}

/// The LLM model variant used for a conversation.
public enum ModelDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case gpt5_4 = "gpt-5.4"
    case gpt5_4_pro = "gpt-5.4-pro"
}

/// The reasoning effort level requested for model responses.
public enum ReasoningEffortDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case low
    case medium
    case high
    case xhigh
}

/// The service tier that determines request priority and cost.
public enum ServiceTierDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case standard = "default"
    case flex
}

/// A conversation as represented by the backend API.
public struct ConversationDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let mode: ConversationModeDTO
    public let createdAt: Date
    public let updatedAt: Date
    public let lastRunID: String?
    public let lastSyncCursor: String?
    public let model: ModelDTO?
    public let reasoningEffort: ReasoningEffortDTO?
    public let agentWorkerReasoningEffort: ReasoningEffortDTO?
    public let serviceTier: ServiceTierDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case mode
        case createdAt
        case updatedAt
        case lastRunID = "lastRunId"
        case lastSyncCursor
        case model
        case reasoningEffort
        case agentWorkerReasoningEffort
        case serviceTier
    }

    /// Creates a conversation DTO with the given fields.
    public init(
        id: String,
        title: String,
        mode: ConversationModeDTO,
        createdAt: Date,
        updatedAt: Date,
        lastRunID: String?,
        lastSyncCursor: String?,
        model: ModelDTO? = nil,
        reasoningEffort: ReasoningEffortDTO? = nil,
        agentWorkerReasoningEffort: ReasoningEffortDTO? = nil,
        serviceTier: ServiceTierDTO? = nil
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunID = lastRunID
        self.lastSyncCursor = lastSyncCursor
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.agentWorkerReasoningEffort = agentWorkerReasoningEffort
        self.serviceTier = serviceTier
    }
}

/// A paginated list of conversations returned by the backend.
public struct ConversationPageDTO: Codable, Equatable, Sendable {
    public let items: [ConversationDTO]
    public let nextCursor: String?
    public let hasMore: Bool

    /// Creates a conversation page with the given items and pagination state.
    public init(
        items: [ConversationDTO],
        nextCursor: String?,
        hasMore: Bool
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

/// The full detail of a conversation including its messages and runs.
public struct ConversationDetailDTO: Codable, Equatable, Sendable {
    public let conversation: ConversationDTO
    public let messages: [MessageDTO]
    public let runs: [RunSummaryDTO]

    /// Creates a detail DTO with the given conversation, messages, and runs.
    public init(
        conversation: ConversationDTO,
        messages: [MessageDTO],
        runs: [RunSummaryDTO]
    ) {
        self.conversation = conversation
        self.messages = messages
        self.runs = runs
    }
}
