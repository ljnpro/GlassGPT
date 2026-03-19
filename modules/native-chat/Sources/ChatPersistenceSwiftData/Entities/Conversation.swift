import ChatDomain
import Foundation
import SwiftData

/// SwiftData entity representing a chat conversation.
@Model
public final class Conversation {
    /// Unique identifier for this conversation.
    public var id: UUID
    /// User-visible title, defaulting to "New Chat".
    public var title: String
    /// Messages belonging to this conversation, cascade-deleted when the conversation is removed.
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    public var messages: [Message]
    /// Timestamp when the conversation was created.
    public var createdAt: Date
    /// Timestamp of the most recent update (message sent or received).
    public var updatedAt: Date
    /// Raw value of the ``ModelType`` used for this conversation.
    public var model: String
    /// Raw value of the ``ReasoningEffort`` level configured for this conversation.
    public var reasoningEffort: String
    /// Whether background mode was enabled for this conversation.
    public var backgroundModeEnabled: Bool
    /// Raw value of the ``ServiceTier`` used for this conversation.
    public var serviceTierRawValue: String

    /// Creates a new conversation with the given parameters.
    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        model: String = ModelType.gpt5_4.rawValue,
        reasoningEffort: String = ReasoningEffort.high.rawValue,
        backgroundModeEnabled: Bool = false,
        serviceTierRawValue: String = ServiceTier.standard.rawValue
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.backgroundModeEnabled = backgroundModeEnabled
        self.serviceTierRawValue = serviceTierRawValue
    }
}
