import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData

/// SwiftData entity representing a chat conversation.
@Model
public final class Conversation {
    /// Unique identifier for this conversation.
    public var id: UUID
    /// Stable server-side identifier for this conversation projection.
    public var serverID: String?
    /// Stable backend account identifier that owns this cached conversation.
    public var syncAccountID: String?
    /// User-visible title, defaulting to "New Chat".
    public var title: String
    /// Messages belonging to this conversation, cascade-deleted when the conversation is removed.
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    public var messages: [Message]
    /// Timestamp when the conversation was created.
    public var createdAt: Date
    /// Timestamp of the most recent update (message sent or received).
    public var updatedAt: Date
    /// The latest server-side run associated with this conversation, if known.
    public var lastRunServerID: String?
    /// The latest sync cursor applied to this conversation projection, if known.
    public var lastSyncCursor: String?
    /// Raw value of the ``ConversationMode`` used for this conversation, or `nil` for chat.
    public var modeRawValue: String?
    /// Raw value of the ``ModelType`` used for this conversation.
    public var model: String
    /// Raw value of the ``ReasoningEffort`` level configured for this conversation.
    public var reasoningEffort: String
    /// Raw value of the worker reasoning effort configured for this Agent conversation, if any.
    public var agentWorkerReasoningEffortRawValue: String?
    /// Raw value of the ``ServiceTier`` used for this conversation.
    public var serviceTierRawValue: String
    /// Encoded hidden Agent-mode state, if this is an Agent conversation.
    public var agentStateData: Data?

    /// Creates a new conversation with the given parameters.
    public init(
        id: UUID = UUID(),
        serverID: String? = nil,
        syncAccountID: String? = nil,
        title: String = "New Chat",
        messages: [Message] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastRunServerID: String? = nil,
        lastSyncCursor: String? = nil,
        modeRawValue: String? = nil,
        model: String = ModelType.gpt5_4.rawValue,
        reasoningEffort: String = ReasoningEffort.medium.rawValue,
        agentWorkerReasoningEffortRawValue: String? = nil,
        serviceTierRawValue: String = ServiceTier.standard.rawValue,
        agentStateData: Data? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.syncAccountID = syncAccountID
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunServerID = lastRunServerID
        self.lastSyncCursor = lastSyncCursor
        self.modeRawValue = modeRawValue
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.agentWorkerReasoningEffortRawValue = agentWorkerReasoningEffortRawValue
        self.serviceTierRawValue = serviceTierRawValue
        self.agentStateData = agentStateData
    }

    /// Typed accessor for the conversation mode, defaulting to ``ConversationMode/chat``.
    public var mode: ConversationMode {
        get { ConversationMode(rawValue: modeRawValue ?? "") ?? .chat }
        set { modeRawValue = newValue == .chat ? nil : newValue.rawValue }
    }

    /// Worker reasoning effort for Agent conversations, when configured.
    public var agentWorkerReasoningEffort: ReasoningEffort? {
        get { agentWorkerReasoningEffortRawValue.flatMap(ReasoningEffort.init(rawValue:)) }
        set { agentWorkerReasoningEffortRawValue = newValue?.rawValue }
    }

    /// Decoded hidden Agent-mode state.
    public var agentConversationState: AgentConversationState? {
        get { PersistencePayloadCoder.decode(AgentConversationState.self, from: agentStateData, owner: "Conversation") }
        set { agentStateData = PersistencePayloadCoder.encode(newValue, owner: "Conversation") }
    }
}
