import ChatDomain
import Foundation

/// Immutable cache record for one conversation projection received from the backend.
public struct ConversationProjectionRecord: Equatable, Sendable {
    public let serverID: String
    public let accountID: String
    public let title: String
    public let mode: ConversationMode
    public let createdAt: Date
    public let updatedAt: Date
    public let lastRunServerID: String?
    public let lastSyncCursor: String?
    public let model: String?
    public let reasoningEffort: String?
    public let agentWorkerReasoningEffort: String?
    public let serviceTier: String?

    public init(
        serverID: String,
        accountID: String,
        title: String,
        mode: ConversationMode,
        createdAt: Date,
        updatedAt: Date,
        lastRunServerID: String?,
        lastSyncCursor: String?,
        model: String?,
        reasoningEffort: String?,
        agentWorkerReasoningEffort: String?,
        serviceTier: String?
    ) {
        self.serverID = serverID
        self.accountID = accountID
        self.title = title
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunServerID = lastRunServerID
        self.lastSyncCursor = lastSyncCursor
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.agentWorkerReasoningEffort = agentWorkerReasoningEffort
        self.serviceTier = serviceTier
    }
}

/// Immutable cache record for one message projection received from the backend.
public struct MessageProjectionRecord: Equatable, Sendable {
    public let serverID: String
    public let accountID: String
    public let role: MessageRole
    public let content: String
    public let thinking: String?
    public let createdAt: Date
    public let completedAt: Date?
    public let serverCursor: String?
    public let serverRunID: String?
    public let annotations: [URLCitation]
    public let toolCalls: [ToolCallInfo]
    public let filePathAnnotations: [FilePathAnnotation]
    public let agentTrace: AgentTurnTrace?

    public init(
        serverID: String,
        accountID: String,
        role: MessageRole,
        content: String,
        thinking: String?,
        createdAt: Date,
        completedAt: Date?,
        serverCursor: String?,
        serverRunID: String?,
        annotations: [URLCitation],
        toolCalls: [ToolCallInfo],
        filePathAnnotations: [FilePathAnnotation],
        agentTrace: AgentTurnTrace?
    ) {
        self.serverID = serverID
        self.accountID = accountID
        self.role = role
        self.content = content
        self.thinking = thinking
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.serverCursor = serverCursor
        self.serverRunID = serverRunID
        self.annotations = annotations
        self.toolCalls = toolCalls
        self.filePathAnnotations = filePathAnnotations
        self.agentTrace = agentTrace
    }
}
