import Foundation

/// A compact leader decision shown in the Agent Process log.
public struct AgentDecision: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier for the recorded decision.
    public let id: String
    /// Decision category used by the process UI.
    public var kind: AgentDecisionKind
    /// Short title shown in the decision log.
    public var title: String
    /// Concise explanation of the decision.
    public var summary: String
    /// Timestamp when the decision was recorded.
    public var createdAt: Date

    /// Creates a compact leader decision for process projection.
    public init(
        id: String = UUID().uuidString,
        kind: AgentDecisionKind,
        title: String,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
    }
}
