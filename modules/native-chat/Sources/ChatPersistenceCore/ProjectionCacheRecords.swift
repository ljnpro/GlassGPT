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

    public init(
        serverID: String,
        accountID: String,
        title: String,
        mode: ConversationMode,
        createdAt: Date,
        updatedAt: Date,
        lastRunServerID: String?,
        lastSyncCursor: String?
    ) {
        self.serverID = serverID
        self.accountID = accountID
        self.title = title
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunServerID = lastRunServerID
        self.lastSyncCursor = lastSyncCursor
    }
}

/// Immutable cache record for one message projection received from the backend.
public struct MessageProjectionRecord: Equatable, Sendable {
    public let serverID: String
    public let accountID: String
    public let role: MessageRole
    public let content: String
    public let createdAt: Date
    public let completedAt: Date?
    public let serverCursor: String?
    public let serverRunID: String?

    public init(
        serverID: String,
        accountID: String,
        role: MessageRole,
        content: String,
        createdAt: Date,
        completedAt: Date?,
        serverCursor: String?,
        serverRunID: String?
    ) {
        self.serverID = serverID
        self.accountID = accountID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.serverCursor = serverCursor
        self.serverRunID = serverRunID
    }
}
