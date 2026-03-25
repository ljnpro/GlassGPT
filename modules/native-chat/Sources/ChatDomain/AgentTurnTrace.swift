import Foundation

/// One persisted worker summary shown in the collapsible Agent process card.
public struct AgentWorkerSummary: Codable, Equatable, Sendable {
    /// The worker role that produced this summary.
    public let role: AgentRole
    /// The revised worker summary after peer review.
    public let summary: String
    /// Explicitly adopted points from the peer round.
    public let adoptedPoints: [String]

    /// Creates a worker summary for the persisted Agent process trace.
    public init(
        role: AgentRole,
        summary: String,
        adoptedPoints: [String] = []
    ) {
        self.role = role
        self.summary = summary
        self.adoptedPoints = adoptedPoints
    }
}

/// Persisted per-answer metadata for Agent mode.
public struct AgentTurnTrace: Codable, Equatable, Sendable {
    /// The compact leader brief summary.
    public let leaderBriefSummary: String
    /// The revised worker summaries.
    public let workerSummaries: [AgentWorkerSummary]
    /// The final completed stage for this run.
    public let completedStage: AgentStage
    /// When the hidden multi-agent process completed.
    public let completedAt: Date
    /// Human-readable outcome string for the run.
    public let outcome: String

    /// Creates persisted per-answer trace metadata for the visible Agent process card.
    public init(
        leaderBriefSummary: String,
        workerSummaries: [AgentWorkerSummary],
        completedStage: AgentStage,
        completedAt: Date = Date(),
        outcome: String
    ) {
        self.leaderBriefSummary = leaderBriefSummary
        self.workerSummaries = workerSummaries
        self.completedStage = completedStage
        self.completedAt = completedAt
        self.outcome = outcome
    }
}
