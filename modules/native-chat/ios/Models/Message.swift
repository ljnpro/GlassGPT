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

    init(
        id: UUID = UUID(),
        role: MessageRole = .user,
        content: String = "",
        thinking: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now,
        conversation: Conversation? = nil
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.thinking = thinking
        self.imageData = imageData
        self.createdAt = createdAt
        self.conversation = conversation
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }
}
