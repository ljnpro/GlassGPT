import Foundation

/// A low-level event used to drive the projected Agent Process snapshot.
public struct AgentEvent: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier for the low-level event.
    public let id: String
    /// Event category used when rebuilding process state.
    public var kind: AgentEventKind
    /// Concise event summary used for debugging and projection.
    public var summary: String
    /// Timestamp when the event was recorded.
    public var createdAt: Date

    /// Creates a low-level Agent event for process projection.
    public init(
        id: String = UUID().uuidString,
        kind: AgentEventKind,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.createdAt = createdAt
    }
}
