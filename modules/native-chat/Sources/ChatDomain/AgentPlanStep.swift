import Foundation

/// One plan step rendered in the live Agent Process tree.
public struct AgentPlanStep: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier for the plan step.
    public let id: String
    /// Parent step identifier when this step is nested under another step.
    public var parentStepID: String?
    /// Owner responsible for the step.
    public var owner: AgentTaskOwner
    /// Current lifecycle status for the step.
    public var status: AgentPlanStepStatus
    /// Short title shown in the plan tree.
    public var title: String
    /// Concise summary of the step's intent or result.
    public var summary: String

    /// Creates a projected plan step for the live or completed Agent Process.
    public init(
        id: String,
        parentStepID: String? = nil,
        owner: AgentTaskOwner,
        status: AgentPlanStepStatus,
        title: String,
        summary: String
    ) {
        self.id = id
        self.parentStepID = parentStepID
        self.owner = owner
        self.status = status
        self.title = title
        self.summary = summary
    }
}
