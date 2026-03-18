import Foundation

public enum DraftRecoveryDisposition: String, Equatable, Sendable {
    case recoverable
    case orphaned
    case stale
}

public struct StoredDraftSnapshot: Equatable, Hashable, Sendable {
    public let messageID: UUID
    public let conversationID: UUID?
    public let responseID: String?
    public let lastSequenceNumber: Int?
    public let createdAt: Date
    public let updatedAt: Date
    public let usedBackgroundMode: Bool

    public init(
        messageID: UUID,
        conversationID: UUID?,
        responseID: String?,
        lastSequenceNumber: Int?,
        createdAt: Date,
        updatedAt: Date,
        usedBackgroundMode: Bool
    ) {
        self.messageID = messageID
        self.conversationID = conversationID
        self.responseID = responseID
        self.lastSequenceNumber = lastSequenceNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usedBackgroundMode = usedBackgroundMode
    }

    public func recoveryDisposition(
        referenceDate: Date,
        staleAfter: TimeInterval
    ) -> DraftRecoveryDisposition {
        guard referenceDate.timeIntervalSince(updatedAt) <= staleAfter else {
            return .stale
        }

        guard conversationID != nil else {
            return .orphaned
        }

        return .recoverable
    }
}

public protocol DraftRepositoryProtocol: Sendable {
    func recoverableDrafts(
        referenceDate: Date,
        staleAfter: TimeInterval
    ) async throws -> [StoredDraftSnapshot]

    func orphanedDrafts(
        referenceDate: Date,
        staleAfter: TimeInterval
    ) async throws -> [StoredDraftSnapshot]
}
