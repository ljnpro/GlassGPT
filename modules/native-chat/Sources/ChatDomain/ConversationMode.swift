/// The top-level interaction mode for a persisted conversation.
public enum ConversationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Standard chat mode.
    case chat
    /// Multi-agent council mode.
    case agent

    /// Stable identifier derived from the raw value.
    public var id: String {
        rawValue
    }

    /// Human-readable label for UI surfaces.
    public var displayName: String {
        switch self {
        case .chat:
            "Chat"
        case .agent:
            "Agent"
        }
    }
}
