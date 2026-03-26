import Foundation

/// The execution owner for a dynamic Agent plan step or delegated task.
public enum AgentTaskOwner: String, Codable, CaseIterable, Identifiable, Sendable {
    case leader
    case workerA
    case workerB
    case workerC

    /// Stable identifier used by SwiftUI and persistence helpers.
    public var id: String {
        rawValue
    }

    /// Human-readable owner name shown in Agent Process UI.
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

    /// Compact owner badge shown in task chips and plan rows.
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

    /// Matching Agent role when the owner represents a worker slot.
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

    /// User-facing status label for plan progress UI.
    public var displayName: String {
        switch self {
        case .planned:
            "Planned"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .completed:
            "Done"
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

    /// User-facing status label for delegated task UI.
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

    /// User-facing label for the task tool policy selector and summaries.
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

    /// User-facing confidence label shown in worker summaries.
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

    /// User-facing stop reason label shown in the completed Agent Process.
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

    /// User-facing activity label shown in the live Agent Process header.
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
            "Done"
        case .failed:
            "Failed"
        }
    }
}
