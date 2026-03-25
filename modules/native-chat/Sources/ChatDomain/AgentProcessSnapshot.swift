import Foundation

/// The projected dynamic process state rendered by the Agent Process disclosure.
public struct AgentProcessSnapshot: Codable, Equatable, Sendable {
    /// Current high-level activity for the run.
    public var activity: AgentProcessActivity
    /// Leader-owned summary of the team's current focus.
    public var currentFocus: String
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
        plan: [AgentPlanStep] = [],
        tasks: [AgentTask] = [],
        decisions: [AgentDecision] = [],
        events: [AgentEvent] = [],
        evidence: [String] = [],
        activeTaskIDs: [String] = [],
        stopReason: AgentStopReason? = nil,
        outcome: String = "",
        updatedAt: Date = Date()
    ) {
        self.activity = activity
        self.currentFocus = currentFocus
        self.plan = plan
        self.tasks = tasks
        self.decisions = decisions
        self.events = events
        self.evidence = evidence
        self.activeTaskIDs = activeTaskIDs
        self.stopReason = stopReason
        self.outcome = outcome
        self.updatedAt = updatedAt
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

        return parts.isEmpty ? "No delegated tasks yet" : parts.joined(separator: " · ")
    }
}
