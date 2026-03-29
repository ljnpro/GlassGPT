import Foundation

public enum ConversationModeDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case chat
    case agent
}

public struct ConversationDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let mode: ConversationModeDTO
    public let createdAt: Date
    public let updatedAt: Date
    public let lastRunID: String?
    public let lastSyncCursor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case mode
        case createdAt
        case updatedAt
        case lastRunID = "lastRunId"
        case lastSyncCursor
    }

    public init(
        id: String,
        title: String,
        mode: ConversationModeDTO,
        createdAt: Date,
        updatedAt: Date,
        lastRunID: String?,
        lastSyncCursor: String?
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunID = lastRunID
        self.lastSyncCursor = lastSyncCursor
    }
}

public enum MessageRoleDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public struct MessageDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let role: MessageRoleDTO
    public let content: String
    public let thinking: String?
    public let createdAt: Date
    public let completedAt: Date?
    public let serverCursor: String?
    public let runID: String?
    public let annotations: [URLCitationDTO]?
    public let toolCalls: [ToolCallInfoDTO]?
    public let filePathAnnotations: [FilePathAnnotationDTO]?
    public let agentTraceJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversationId"
        case role
        case content
        case thinking
        case createdAt
        case completedAt
        case serverCursor
        case runID = "runId"
        case annotations
        case toolCalls
        case filePathAnnotations
        case agentTraceJSON
    }

    public init(
        id: String,
        conversationID: String,
        role: MessageRoleDTO,
        content: String,
        thinking: String?,
        createdAt: Date,
        completedAt: Date?,
        serverCursor: String?,
        runID: String?,
        annotations: [URLCitationDTO]?,
        toolCalls: [ToolCallInfoDTO]?,
        filePathAnnotations: [FilePathAnnotationDTO]?,
        agentTraceJSON: String?
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.thinking = thinking
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.serverCursor = serverCursor
        self.runID = runID
        self.annotations = annotations
        self.toolCalls = toolCalls
        self.filePathAnnotations = filePathAnnotations
        self.agentTraceJSON = agentTraceJSON
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

public struct CreateConversationRequestDTO: Codable, Equatable, Sendable {
    public let title: String
    public let mode: ConversationModeDTO

    public init(title: String, mode: ConversationModeDTO) {
        self.title = title
        self.mode = mode
    }
}

public struct CreateMessageRequestDTO: Codable, Equatable, Sendable {
    public let content: String

    public init(content: String) {
        self.content = content
    }
}
