import Foundation

/// The projected dynamic process state rendered by the Agent Process disclosure.
public struct AgentProcessSnapshot: Codable, Equatable, Sendable {
    public var activity: AgentProcessActivity
    public var currentFocus: String
    public var plan: [AgentPlanStep]
    public var tasks: [AgentTask]
    public var decisions: [AgentDecision]
    public var events: [AgentEvent]
    public var evidence: [String]
    public var activeTaskIDs: [String]
    public var stopReason: AgentStopReason?
    public var outcome: String
    public var updatedAt: Date

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

    public var activeTasks: [AgentTask] {
        tasks.filter { activeTaskIDs.contains($0.id) }
    }

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
