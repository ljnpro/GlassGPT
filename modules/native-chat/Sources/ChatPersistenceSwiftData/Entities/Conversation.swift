import ChatDomain
import Foundation
import SwiftData

@Model
public final class Conversation {
    public var id: UUID
    public var title: String
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    public var messages: [Message]
    public var createdAt: Date
    public var updatedAt: Date
    public var model: String
    public var reasoningEffort: String
    public var backgroundModeEnabled: Bool
    public var serviceTierRawValue: String

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
