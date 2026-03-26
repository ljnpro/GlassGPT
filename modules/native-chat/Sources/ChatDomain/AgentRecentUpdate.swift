import Foundation

/// Semantic source for one projected recent update in the Agent Process UI.
public enum AgentProcessUpdateSource: String, Codable, CaseIterable, Sendable {
    /// System-owned update not attributable to one participant.
    case system
    /// Leader-owned process milestone.
    case leader
    /// Worker A milestone.
    case workerA
    /// Worker B milestone.
    case workerB
    /// Worker C milestone.
    case workerC
    /// Recovery-specific runtime milestone.
    case recovery

    /// Builds an update source from a runtime participant role when possible.
    public init(role: AgentRole?) {
        switch role {
        case .leader:
            self = .leader
        case .workerA:
            self = .workerA
        case .workerB:
            self = .workerB
        case .workerC:
            self = .workerC
        case nil:
            self = .system
        }
    }
}

/// Semantic category for one projected recent update in the Agent Process UI.
public enum AgentProcessUpdateKind: String, Codable, CaseIterable, Sendable {
    /// Compatibility-mapped legacy update with no richer semantics.
    case legacy
    /// Agent run started.
    case runStarted
    /// Leader entered or materially advanced a planning/review phase.
    case leaderPhase
    /// Plan changed materially.
    case planUpdated
    /// Worker wave was queued.
    case workerWaveQueued
    /// One worker started.
    case workerStarted
    /// One worker finished successfully.
    case workerCompleted
    /// One worker failed.
    case workerFailed
    /// Internal council completed.
    case councilCompleted
    /// Recovery progress or failure.
    case recovery
}

/// One bounded recent update shown in the live Agent Process disclosure.
public struct AgentProcessUpdate: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier for the update row.
    public let id: String
    /// Semantic category for the projected update.
    public var kind: AgentProcessUpdateKind
    /// Runtime source that produced the update.
    public var source: AgentProcessUpdateSource
    /// The run phase this update belongs to, when known.
    public var phase: AgentRunPhase?
    /// The worker task id that produced the update, when relevant.
    public var taskID: String?
    /// The low-level source event id that produced the update, when relevant.
    public var sourceEventID: String?
    /// Concise user-facing summary for the update row.
    public var summary: String
    /// First creation timestamp for the update.
    public var createdAt: Date
    /// Last mutation timestamp for the update.
    public var updatedAt: Date

    /// Creates a semantic Agent Process recent update.
    public init(
        id: String = UUID().uuidString,
        kind: AgentProcessUpdateKind,
        source: AgentProcessUpdateSource,
        phase: AgentRunPhase? = nil,
        taskID: String? = nil,
        sourceEventID: String? = nil,
        summary: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.phase = phase
        self.taskID = taskID
        self.sourceEventID = sourceEventID
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Compatibility mapping for persisted 4.12.5 string-only updates.
    public static func legacy(_ summary: String) -> AgentProcessUpdate {
        AgentProcessUpdate(
            kind: .legacy,
            source: .system,
            summary: summary
        )
    }
}
