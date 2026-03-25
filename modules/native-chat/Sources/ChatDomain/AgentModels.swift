import Foundation

/// The hidden internal roles that participate in Agent mode.
public enum AgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case leader
    case workerA
    case workerB
    case workerC

    /// Stable identifier derived from the raw value.
    public var id: String {
        rawValue
    }

    /// Human-readable label for UI surfaces.
    public var displayName: String {
        switch self {
        case .leader:
            "Leader"
        case .workerA:
            "Worker A"
        case .workerB:
            "Worker B"
        case .workerC:
            "Worker C"
        }
    }

    /// Compact badge label for progress UI.
    public var shortLabel: String {
        switch self {
        case .leader:
            "L"
        case .workerA:
            "A"
        case .workerB:
            "B"
        case .workerC:
            "C"
        }
    }
}

/// The visible execution stages for one Agent turn.
public enum AgentStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case leaderBrief
    case workersRoundOne
    case crossReview
    case finalSynthesis

    /// Stable identifier derived from the raw value.
    public var id: String {
        rawValue
    }

    /// Human-readable label for UI surfaces.
    public var displayName: String {
        switch self {
        case .leaderBrief:
            "Leader brief"
        case .workersRoundOne:
            "Workers round 1"
        case .crossReview:
            "Cross-review"
        case .finalSynthesis:
            "Final synthesis"
        }
    }
}

/// The persisted hidden state for one Agent conversation.
public struct AgentConversationState: Codable, Equatable, Sendable {
    /// The leader chain response identifier.
    public var leaderResponseID: String?
    /// Worker A chain response identifier.
    public var workerAResponseID: String?
    /// Worker B chain response identifier.
    public var workerBResponseID: String?
    /// Worker C chain response identifier.
    public var workerCResponseID: String?
    /// The currently active stage, if a foreground run is underway.
    public var currentStage: AgentStage?
    /// Last update timestamp for the hidden state payload.
    public var updatedAt: Date

    /// Creates persisted hidden state for one Agent conversation and its per-role response chains.
    public init(
        leaderResponseID: String? = nil,
        workerAResponseID: String? = nil,
        workerBResponseID: String? = nil,
        workerCResponseID: String? = nil,
        currentStage: AgentStage? = nil,
        updatedAt: Date = .now
    ) {
        self.leaderResponseID = leaderResponseID
        self.workerAResponseID = workerAResponseID
        self.workerBResponseID = workerBResponseID
        self.workerCResponseID = workerCResponseID
        self.currentStage = currentStage
        self.updatedAt = updatedAt
    }

    /// Returns the current response identifier for the given internal role.
    public func responseID(for role: AgentRole) -> String? {
        switch role {
        case .leader:
            leaderResponseID
        case .workerA:
            workerAResponseID
        case .workerB:
            workerBResponseID
        case .workerC:
            workerCResponseID
        }
    }

    /// Updates the response identifier for the given role.
    public mutating func setResponseID(
        _ responseID: String?,
        for role: AgentRole,
        updatedAt: Date = .now
    ) {
        switch role {
        case .leader:
            leaderResponseID = responseID
        case .workerA:
            workerAResponseID = responseID
        case .workerB:
            workerBResponseID = responseID
        case .workerC:
            workerCResponseID = responseID
        }
        self.updatedAt = updatedAt
    }
}

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
        adoptedPoints: [String]
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
        completedAt: Date = .now,
        outcome: String
    ) {
        self.leaderBriefSummary = leaderBriefSummary
        self.workerSummaries = workerSummaries
        self.completedStage = completedStage
        self.completedAt = completedAt
        self.outcome = outcome
    }
}
