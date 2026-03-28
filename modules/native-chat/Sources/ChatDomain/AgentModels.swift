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

/// User-configurable runtime settings for one Agent conversation.
public struct AgentConversationConfiguration: Codable, Equatable, Sendable {
    /// Reasoning effort used by the leader.
    public var leaderReasoningEffort: ReasoningEffort
    /// Shared reasoning effort used by all three workers.
    public var workerReasoningEffort: ReasoningEffort
    /// Service tier used by the Agent council.
    public var serviceTier: ServiceTier

    /// Creates Agent configuration values for one conversation.
    public init(
        leaderReasoningEffort: ReasoningEffort = .high,
        workerReasoningEffort: ReasoningEffort = .low,
        serviceTier: ServiceTier = .standard
    ) {
        self.leaderReasoningEffort = leaderReasoningEffort
        self.workerReasoningEffort = workerReasoningEffort
        self.serviceTier = serviceTier
    }

    /// Convenience toggle for switching between standard and flex service tiers.
    public var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
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

    /// Compatibility bridge into the newer dynamic process activity model.
    public var compatibilityProcessActivity: AgentProcessActivity {
        switch self {
        case .leaderBrief:
            .triage
        case .workersRoundOne:
            .delegation
        case .crossReview:
            .reviewing
        case .finalSynthesis:
            .synthesis
        }
    }
}

/// Per-worker execution state rendered in the Agent progress summary.
public struct AgentWorkerProgress: Codable, Equatable, Identifiable, Sendable {
    /// The worker role represented by this progress item.
    public let role: AgentRole
    /// The current execution status for that worker role.
    public var status: Status

    /// Supported progress states for one worker.
    public enum Status: String, Codable, Equatable, Sendable {
        case waiting
        case running
        case completed
        case failed
    }

    /// Stable identifier derived from the worker role.
    public var id: AgentRole {
        role
    }

    /// Creates worker progress for one role.
    public init(role: AgentRole, status: Status) {
        self.role = role
        self.status = status
    }

    /// The default waiting state for a three-worker stage.
    public static let defaultProgress: [AgentWorkerProgress] = [
        AgentWorkerProgress(role: .workerA, status: .waiting),
        AgentWorkerProgress(role: .workerB, status: .waiting),
        AgentWorkerProgress(role: .workerC, status: .waiting)
    ]
}
