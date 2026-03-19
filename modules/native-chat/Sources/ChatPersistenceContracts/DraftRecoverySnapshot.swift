import Foundation

/// Indicates whether a stored draft can be recovered, is orphaned, or has expired.
public enum DraftRecoveryDisposition: String, Equatable, Sendable {
    /// The draft has a valid conversation and is within the staleness window.
    case recoverable
    /// The draft has no associated conversation and cannot be recovered.
    case orphaned
    /// The draft has exceeded the staleness threshold and should be discarded.
    case stale
}

/// A lightweight snapshot of a persisted draft message used for recovery decisions.
public struct StoredDraftSnapshot: Equatable, Hashable, Sendable {
    /// The unique identifier of the draft message.
    public let messageID: UUID
    /// The conversation this draft belongs to, or `nil` if orphaned.
    public let conversationID: UUID?
    /// The API response identifier associated with this draft, if streaming began.
    public let responseID: String?
    /// The last received event sequence number, if any.
    public let lastSequenceNumber: Int?
    /// When the draft was originally created.
    public let createdAt: Date
    /// When the draft was last updated.
    public let updatedAt: Date
    /// Whether this draft was created with background mode enabled.
    public let usedBackgroundMode: Bool

    /// Creates a new stored draft snapshot.
    /// - Parameters:
    ///   - messageID: The unique identifier of the draft message.
    ///   - conversationID: The owning conversation identifier.
    ///   - responseID: The API response identifier.
    ///   - lastSequenceNumber: The last received sequence number.
    ///   - createdAt: The creation timestamp.
    ///   - updatedAt: The last update timestamp.
    ///   - usedBackgroundMode: Whether background mode was enabled.
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

    /// Evaluates the recovery disposition of this draft.
    /// - Parameters:
    ///   - referenceDate: The current date used to evaluate staleness.
    ///   - staleAfter: The maximum age in seconds before a draft is considered stale.
    /// - Returns: The recovery disposition for this draft.
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

/// Repository interface for querying persisted draft messages.
public protocol DraftRepositoryProtocol: Sendable {
    /// Returns drafts that are eligible for recovery based on age.
    /// - Parameters:
    ///   - referenceDate: The current date used to evaluate staleness.
    ///   - staleAfter: The maximum age in seconds before a draft is considered stale.
    /// - Returns: An array of recoverable draft snapshots.
    /// - Throws: If the persistence layer encounters an error.
    func recoverableDrafts(
        referenceDate: Date,
        staleAfter: TimeInterval
    ) async throws -> [StoredDraftSnapshot]

    /// Returns drafts that have no associated conversation.
    /// - Parameters:
    ///   - referenceDate: The current date used to evaluate staleness.
    ///   - staleAfter: The maximum age in seconds before a draft is considered stale.
    /// - Returns: An array of orphaned draft snapshots.
    /// - Throws: If the persistence layer encounters an error.
    func orphanedDrafts(
        referenceDate: Date,
        staleAfter: TimeInterval
    ) async throws -> [StoredDraftSnapshot]
}
