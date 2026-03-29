import Foundation

public enum ConversationModeDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case chat
    case agent
}

public enum ModelDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case gpt5_4 = "gpt-5.4"
    case gpt5_4_pro = "gpt-5.4-pro"
}

public enum ReasoningEffortDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case low
    case medium
    case high
    case xhigh
}

public enum ServiceTierDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case standard = "default"
    case flex
}

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

public struct ConversationPageDTO: Codable, Equatable, Sendable {
    public let items: [ConversationDTO]
    public let nextCursor: String?
    public let hasMore: Bool

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

public struct ConversationDetailDTO: Codable, Equatable, Sendable {
    public let conversation: ConversationDTO
    public let messages: [MessageDTO]
    public let runs: [RunSummaryDTO]

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
