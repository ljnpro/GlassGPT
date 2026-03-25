import Foundation

/// The execution owner for a dynamic Agent plan step or delegated task.
public enum AgentTaskOwner: String, Codable, CaseIterable, Identifiable, Sendable {
    case leader
    case workerA
    case workerB
    case workerC

    public var id: String {
        rawValue
    }

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

    public var role: AgentRole? {
        switch self {
        case .leader:
            nil
        case .workerA:
            .workerA
        case .workerB:
            .workerB
        case .workerC:
            .workerC
        }
    }
}

/// The lifecycle state for one Agent plan step.
public enum AgentPlanStepStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case running
    case blocked
    case completed
    case discarded

    public var displayName: String {
        switch self {
        case .planned:
            "Planned"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .completed:
            "Completed"
        case .discarded:
            "Discarded"
        }
    }
}

/// The lifecycle state for one delegated Agent task.
public enum AgentTaskStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case blocked
    case completed
    case failed
    case discarded

    public var displayName: String {
        switch self {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .discarded:
            "Discarded"
        }
    }
}

/// Whether a delegated task may use tools or should stay reasoning-only.
public enum AgentToolPolicy: String, Codable, Sendable {
    case enabled
    case reasoningOnly

    public var displayName: String {
        switch self {
        case .enabled:
            "Tools"
        case .reasoningOnly:
            "Reasoning Only"
        }
    }
}

/// Confidence reported by a delegated worker task.
public enum AgentConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    public var displayName: String {
        rawValue.capitalized
    }
}

/// High-level decision categories emitted by the leader throughout a run.
public enum AgentDecisionKind: String, Codable, CaseIterable, Sendable {
    case triage
    case localPass
    case delegate
    case revise
    case adopt
    case discard
    case clarify
    case finish
}

/// Stop reasons for a dynamic Agent run.
public enum AgentStopReason: String, Codable, CaseIterable, Sendable {
    case sufficientAnswer
    case clarificationRequired
    case budgetReached
    case toolFailure
    case cancelled
    case incomplete

    public var displayName: String {
        switch self {
        case .sufficientAnswer:
            "Answer completed"
        case .clarificationRequired:
            "Needs clarification"
        case .budgetReached:
            "Budget reached"
        case .toolFailure:
            "Tool failure"
        case .cancelled:
            "Stopped"
        case .incomplete:
            "Incomplete"
        }
    }
}

/// The current live activity for the Agent process disclosure.
public enum AgentProcessActivity: String, Codable, CaseIterable, Sendable {
    case triage
    case localPass
    case delegation
    case reviewing
    case synthesis
    case waitingForUser
    case completed
    case failed

    public var displayName: String {
        switch self {
        case .triage:
            "Leader triage"
        case .localPass:
            "Leader local pass"
        case .delegation:
            "Delegating work"
        case .reviewing:
            "Leader review"
        case .synthesis:
            "Final synthesis"
        case .waitingForUser:
            "Waiting for user"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }
}

/// Supported event categories for projecting Agent process UI state.
public enum AgentEventKind: String, Codable, CaseIterable, Sendable {
    case started
    case focusUpdated
    case planUpdated
    case taskQueued
    case taskStarted
    case taskCompleted
    case taskFailed
    case decisionRecorded
    case evidenceRecorded
    case synthesisStarted
    case completed
    case failed
}

/// One plan step rendered in the live Agent Process tree.
public struct AgentPlanStep: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var parentStepID: String?
    public var owner: AgentTaskOwner
    public var status: AgentPlanStepStatus
    public var title: String
    public var summary: String

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
