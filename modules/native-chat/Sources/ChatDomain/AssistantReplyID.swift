import Foundation

/// A strongly-typed identifier for an assistant reply within a conversation.
public struct AssistantReplyID: Hashable, Sendable {
    /// The underlying UUID backing this identifier.
    public let rawValue: UUID

    /// Creates a new assistant reply identifier.
    /// - Parameter rawValue: The UUID to use. Defaults to a new random UUID.
    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
