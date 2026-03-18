import Foundation

public struct StoredConversationSnapshot: Equatable, Hashable, Sendable {
    public let id: UUID
    public let title: String?
    public let modelIdentifier: String
    public let reasoningEffortIdentifier: String
    public let backgroundModeEnabled: Bool
    public let serviceTierIdentifier: String
    public let updatedAt: Date

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

public protocol ConversationRepositoryProtocol: Sendable {
    func mostRecentConversation() async throws -> StoredConversationSnapshot?
    func conversation(id: UUID) async throws -> StoredConversationSnapshot?
}

public protocol MessagePersistenceProtocol: Sendable {
    func finalizeMessage(
        id: UUID,
        responseID: String?,
        lastSequenceNumber: Int?,
        payloadRevision: String?
    ) async throws
}
