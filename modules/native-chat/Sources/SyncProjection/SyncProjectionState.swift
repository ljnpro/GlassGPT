import BackendContracts
import Foundation

public struct SyncProjectionState: Equatable, Sendable {
    public let cursor: SyncCursor?
    public let conversationsByID: [String: ConversationDTO]
    public let messagesByID: [String: MessageDTO]
    public let runsByID: [String: RunSummaryDTO]
    public let artifactsByID: [String: ArtifactDTO]

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
