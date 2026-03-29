import Foundation

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
