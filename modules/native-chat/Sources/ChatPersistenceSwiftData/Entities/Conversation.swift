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
    /// Raw value of the ``ConversationMode`` used for this conversation, or `nil` for chat.
    public var modeRawValue: String?
    /// Raw value of the ``ModelType`` used for this conversation.
    public var model: String
    /// Raw value of the ``ReasoningEffort`` level configured for this conversation.
    public var reasoningEffort: String
    /// Whether background mode was enabled for this conversation.
    public var backgroundModeEnabled: Bool
    /// Raw value of the ``ServiceTier`` used for this conversation.
    public var serviceTierRawValue: String
    /// Encoded hidden Agent-mode state, if this is an Agent conversation.
    public var agentStateData: Data?

    /// Creates a new conversation with the given parameters.
    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        modeRawValue: String? = nil,
        model: String = ModelType.gpt5_4.rawValue,
        reasoningEffort: String = ReasoningEffort.high.rawValue,
        backgroundModeEnabled: Bool = false,
        serviceTierRawValue: String = ServiceTier.standard.rawValue,
        agentStateData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modeRawValue = modeRawValue
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.backgroundModeEnabled = backgroundModeEnabled
        self.serviceTierRawValue = serviceTierRawValue
        self.agentStateData = agentStateData
    }

    /// Typed accessor for the conversation mode, defaulting to ``ConversationMode/chat``.
    public var mode: ConversationMode {
        get { ConversationMode(rawValue: modeRawValue ?? "") ?? .chat }
        set { modeRawValue = newValue == .chat ? nil : newValue.rawValue }
    }

    /// Decoded hidden Agent-mode state.
    public var agentConversationState: AgentConversationState? {
        get { decodePayload(AgentConversationState.self, from: agentStateData) }
        set { agentStateData = encodePayload(newValue) }
    }

    private func decodePayload<T: Decodable>(_: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            NSLog(
                "%@",
                "Conversation payload decode failed for \(String(describing: T.self)): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func encodePayload<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        do {
            return try JSONEncoder().encode(value)
        } catch {
            NSLog(
                "%@",
                "Conversation payload encode failed for \(String(describing: T.self)): \(error.localizedDescription)"
            )
            return nil
        }
    }
}
