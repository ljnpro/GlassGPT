import BackendContracts
import Foundation

/// In-memory projection of backend state built from applied sync events.
public struct SyncProjectionState: Equatable, Sendable {
    public let cursor: SyncCursor?
    public let conversationsByID: [String: ConversationDTO]
    public let messagesByID: [String: MessageDTO]
    public let runsByID: [String: RunSummaryDTO]
    public let artifactsByID: [String: ArtifactDTO]

    /// Creates a projection state with the given cursor and entity maps.
    public init(
        cursor: SyncCursor? = nil,
        conversationsByID: [String: ConversationDTO] = [:],
        messagesByID: [String: MessageDTO] = [:],
        runsByID: [String: RunSummaryDTO] = [:],
        artifactsByID: [String: ArtifactDTO] = [:]
    ) {
        self.cursor = cursor
        self.conversationsByID = conversationsByID
        self.messagesByID = messagesByID
        self.runsByID = runsByID
        self.artifactsByID = artifactsByID
    }

    public static let empty = SyncProjectionState()

    /// Returns all projected messages for the given conversation, sorted by creation date.
    public func messages(forConversationID conversationID: String) -> [MessageDTO] {
        messagesByID.values
            .filter { $0.conversationID == conversationID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }

                return lhs.createdAt < rhs.createdAt
            }
    }

    /// Returns all projected runs for the given conversation, sorted by creation date.
    public func runs(forConversationID conversationID: String) -> [RunSummaryDTO] {
        runsByID.values
            .filter { $0.conversationID == conversationID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }

                return lhs.createdAt < rhs.createdAt
            }
    }
}
