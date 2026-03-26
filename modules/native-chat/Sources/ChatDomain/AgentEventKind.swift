import Foundation

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
