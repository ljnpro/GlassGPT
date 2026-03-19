import Foundation

/// A lightweight snapshot of a persisted conversation used for restoration.
public struct StoredConversationSnapshot: Equatable, Hashable, Sendable {
    /// The unique identifier of the conversation.
    public let id: UUID
    /// The conversation title, or `nil` if untitled.
    public let title: String?
    /// The raw string identifier of the model used for this conversation.
    public let modelIdentifier: String
    /// The raw string identifier of the reasoning effort level.
    public let reasoningEffortIdentifier: String
    /// Whether background mode was enabled for this conversation.
    public let backgroundModeEnabled: Bool
    /// The raw string identifier of the service tier.
    public let serviceTierIdentifier: String
    /// When the conversation was last updated.
    public let updatedAt: Date

    /// Creates a new stored conversation snapshot.
    /// - Parameters:
    ///   - id: The unique identifier.
    ///   - title: The conversation title.
    ///   - modelIdentifier: The model identifier string.
    ///   - reasoningEffortIdentifier: The reasoning effort identifier string.
    ///   - backgroundModeEnabled: Whether background mode was enabled.
    ///   - serviceTierIdentifier: The service tier identifier string.
    ///   - updatedAt: The last update timestamp.
    public init(
        id: UUID,
        title: String?,
        modelIdentifier: String,
        reasoningEffortIdentifier: String,
        backgroundModeEnabled: Bool,
        serviceTierIdentifier: String,
        updatedAt: Date
    ) {
        self.id = id
        self.title = Self.normalizedTitle(title)
        self.modelIdentifier = modelIdentifier
        self.reasoningEffortIdentifier = reasoningEffortIdentifier
        self.backgroundModeEnabled = backgroundModeEnabled
        self.serviceTierIdentifier = serviceTierIdentifier
        self.updatedAt = updatedAt
    }

    /// Whether this conversation uses any non-default configuration settings.
    public var hasCustomConfiguration: Bool {
        backgroundModeEnabled
            || reasoningEffortIdentifier != "none"
            || serviceTierIdentifier != "standard"
    }

    private static func normalizedTitle(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Repository interface for querying persisted conversations.
public protocol ConversationRepositoryProtocol: Sendable {
    /// Returns the most recently updated conversation, if any.
    /// - Returns: The most recent conversation snapshot, or `nil`.
    /// - Throws: If the persistence layer encounters an error.
    func mostRecentConversation() async throws -> StoredConversationSnapshot?

    /// Returns the conversation with the given identifier, if it exists.
    /// - Parameter id: The conversation identifier to look up.
    /// - Returns: The matching conversation snapshot, or `nil`.
    /// - Throws: If the persistence layer encounters an error.
    func conversation(id: UUID) async throws -> StoredConversationSnapshot?
}

/// Interface for finalizing draft messages into persisted messages.
public protocol MessagePersistenceProtocol: Sendable {
    /// Marks a draft message as finalized with its API response metadata.
    /// - Parameters:
    ///   - id: The message identifier to finalize.
    ///   - responseID: The API response identifier, if available.
    ///   - lastSequenceNumber: The last received event sequence number.
    ///   - payloadRevision: An opaque revision string for the message payload.
    /// - Throws: If the persistence operation fails.
    func finalizeMessage(
        id: UUID,
        responseID: String?,
        lastSequenceNumber: Int?,
        payloadRevision: String?
    ) async throws
}
