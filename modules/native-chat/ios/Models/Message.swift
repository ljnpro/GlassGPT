import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var roleRawValue: String
    var content: String
    var thinking: String?
    var imageData: Data?
    var createdAt: Date
    var conversation: Conversation?

    /// The OpenAI response ID (from response.created event).
    /// Used to poll for complete response if streaming was interrupted.
    var responseId: String?

    /// Whether this message has been fully received.
    /// false = still streaming or interrupted draft.
    var isComplete: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole = .user,
        content: String = "",
        thinking: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now,
        conversation: Conversation? = nil,
        responseId: String? = nil,
        isComplete: Bool = true
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.thinking = thinking
        self.imageData = imageData
        self.createdAt = createdAt
        self.conversation = conversation
        self.responseId = responseId
        self.isComplete = isComplete
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }
}
