import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date
    var model: String
    var reasoningEffort: String
    var backgroundModeEnabled: Bool
    var serviceTierRawValue: String

    init(
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
