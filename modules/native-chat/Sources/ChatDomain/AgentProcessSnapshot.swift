import Foundation

/// The projected dynamic process state rendered by the Agent Process disclosure.
public struct AgentProcessSnapshot: Codable, Equatable, Sendable {
    /// Current high-level activity for the run.
    public var activity: AgentProcessActivity
    /// Leader-owned summary of the team's current focus.
    public var currentFocus: String
    /// Stable accepted leader focus used for final synthesis and completed traces.
    public var leaderAcceptedFocus: String
    /// Short transient leader status shown while hidden phases are running.
    public var leaderLiveStatus: String
    /// Short transient leader summary shown while hidden phases are running.
    public var leaderLiveSummary: String
    /// Projected plan tree shown in the Agent Process.
    public var plan: [AgentPlanStep]
    /// Delegated tasks tracked for the current run.
    public var tasks: [AgentTask]
    /// Compact leader decisions recorded so far.
    public var decisions: [AgentDecision]
    /// Low-level events used to rebuild process state.
    public var events: [AgentEvent]
    /// Adopted evidence items surfaced to the UI and synthesis.
    public var evidence: [String]
    /// Identifiers for tasks that are actively running.
    public var activeTaskIDs: [String]
    /// Legacy string-based process updates kept for compatibility decoding/encoding.
    public var recentUpdates: [String]
    /// Semantic milestone updates shown in the live disclosure.
    public var recentUpdateItems: [AgentProcessUpdate]
    /// Current recovery status for the live process projection.
    public var recoveryState: AgentRecoveryState
    /// Terminal stop reason when the run has concluded.
    public var stopReason: AgentStopReason?
    /// Final outcome summary for the completed run.
    public var outcome: String
    /// Last mutation timestamp for the process snapshot.
    public var updatedAt: Date

    /// Creates a projected process snapshot for live Agent UI and persistence.
    public init(
        activity: AgentProcessActivity = .triage,
        currentFocus: String = "",
        leaderAcceptedFocus: String = "",
        leaderLiveStatus: String = "",
        leaderLiveSummary: String = "",
        plan: [AgentPlanStep] = [],
        tasks: [AgentTask] = [],
        decisions: [AgentDecision] = [],
        events: [AgentEvent] = [],
        evidence: [String] = [],
        activeTaskIDs: [String] = [],
        recentUpdates: [String] = [],
        recentUpdateItems: [AgentProcessUpdate] = [],
        recoveryState: AgentRecoveryState = .idle,
        stopReason: AgentStopReason? = nil,
        outcome: String = "",
        updatedAt: Date = Date()
    ) {
        let resolvedRecentUpdateItems = recentUpdateItems.isEmpty
            ? recentUpdates.map(AgentProcessUpdate.legacy)
            : recentUpdateItems
        self.activity = activity
        self.currentFocus = currentFocus
        self.leaderAcceptedFocus = leaderAcceptedFocus.isEmpty ? currentFocus : leaderAcceptedFocus
        self.leaderLiveStatus = leaderLiveStatus
        self.leaderLiveSummary = leaderLiveSummary
        self.plan = plan
        self.tasks = tasks
        self.decisions = decisions
        self.events = events
        self.evidence = evidence
        self.activeTaskIDs = activeTaskIDs
        self.recentUpdates = recentUpdates.isEmpty
            ? resolvedRecentUpdateItems.map(\.summary)
            : recentUpdates
        self.recentUpdateItems = resolvedRecentUpdateItems
        self.recoveryState = recoveryState
        self.stopReason = stopReason
        self.outcome = outcome
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case activity
        case currentFocus
        case leaderAcceptedFocus
        case leaderLiveStatus
        case leaderLiveSummary
        case plan
        case tasks
        case decisions
        case events
        case evidence
        case activeTaskIDs
        case recentUpdates
        case recentUpdateItems
        case recoveryState
        case stopReason
        case outcome
        case updatedAt
    }

    /// Decodes an Agent process snapshot while backfilling newer live projection fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity = try container.decodeIfPresent(AgentProcessActivity.self, forKey: .activity) ?? .triage
        currentFocus = try container.decodeIfPresent(String.self, forKey: .currentFocus) ?? ""
        leaderAcceptedFocus = try container.decodeIfPresent(String.self, forKey: .leaderAcceptedFocus)
            ?? currentFocus
        leaderLiveStatus = try container.decodeIfPresent(String.self, forKey: .leaderLiveStatus) ?? ""
        leaderLiveSummary = try container.decodeIfPresent(String.self, forKey: .leaderLiveSummary) ?? ""
        plan = try container.decodeIfPresent([AgentPlanStep].self, forKey: .plan) ?? []
        tasks = try container.decodeIfPresent([AgentTask].self, forKey: .tasks) ?? []
        decisions = try container.decodeIfPresent([AgentDecision].self, forKey: .decisions) ?? []
        events = try container.decodeIfPresent([AgentEvent].self, forKey: .events) ?? []
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        activeTaskIDs = try container.decodeIfPresent([String].self, forKey: .activeTaskIDs) ?? []
        if container.contains(.recentUpdateItems) {
            recentUpdateItems = try container.decodeIfPresent(
                [AgentProcessUpdate].self,
                forKey: .recentUpdateItems
            ) ?? []
        } else {
            recentUpdateItems = []
        }
        recentUpdates = try container.decodeIfPresent([String].self, forKey: .recentUpdates) ?? []
        if recentUpdateItems.isEmpty, !recentUpdates.isEmpty {
            recentUpdateItems = recentUpdates.map(AgentProcessUpdate.legacy)
        }
        if recentUpdates.isEmpty, !recentUpdateItems.isEmpty {
            recentUpdates = recentUpdateItems.map(\.summary)
        }
        recoveryState = try container.decodeIfPresent(AgentRecoveryState.self, forKey: .recoveryState) ?? .idle
        stopReason = try container.decodeIfPresent(AgentStopReason.self, forKey: .stopReason)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// Tasks currently marked active by the runtime.
    public var activeTasks: [AgentTask] {
        tasks.filter { activeTaskIDs.contains($0.id) }
    }

    /// Compact textual progress summary for the disclosure header.
    public var progressSummary: String {
        let running = tasks.count(where: { $0.status == .running })
        let completed = tasks.count(where: { $0.status == .completed })
        let blocked = tasks.count(where: { $0.status == .blocked || $0.status == .failed })

        var parts: [String] = []
        if running > 0 {
            parts.append("\(running) running")
        }
        if completed > 0 {
            parts.append("\(completed) done")
        }
        if blocked > 0 {
            parts.append("\(blocked) blocked")
        }

        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }

        let leaderStatus = leaderLiveStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leaderStatus.isEmpty {
            return leaderStatus
        }

        return activity.displayName
    }
}
