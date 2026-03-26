import Foundation

/// A leader-proposed follow-up idea returned by a worker.
public struct AgentTaskSuggestion: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier for the follow-up suggestion.
    public let id: String
    /// Short title describing the suggested follow-up.
    public var title: String
    /// Goal the suggested follow-up should accomplish.
    public var goal: String
    /// Recommended tool policy for the suggested follow-up.
    public var toolPolicy: AgentToolPolicy

    /// Creates a worker-suggested follow-up task recommendation.
    public init(
        id: String = UUID().uuidString,
        title: String,
        goal: String,
        toolPolicy: AgentToolPolicy
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.toolPolicy = toolPolicy
    }
}
