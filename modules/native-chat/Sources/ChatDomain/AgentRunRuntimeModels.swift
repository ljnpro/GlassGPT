import Foundation

/// The persisted execution phase for an in-flight Agent run.
public enum AgentRunPhase: String, Codable, CaseIterable, Sendable {
    /// Uploading the current turn's attachments before any hidden work starts.
    case attachmentUpload
    /// The leader is scoping the request and shaping the initial plan.
    case leaderTriage
    /// The leader is doing short blocking reasoning before delegation.
    case leaderLocalPass
    /// One bounded worker wave is running.
    case workerWave
    /// The leader is reviewing completed worker results.
    case leaderReview
    /// The visible final answer is being synthesized.
    case finalSynthesis
    /// The runtime is reconnecting to a previously started server response.
    case reconnecting
    /// The runtime is replaying from the latest durable checkpoint.
    case replayingCheckpoint
    /// The turn completed successfully.
    case completed
    /// The turn failed or stopped before completion.
    case failed

    /// Human-readable label for the current persisted phase.
    public var displayName: String {
        switch self {
        case .attachmentUpload:
            "Uploading attachments"
        case .leaderTriage:
            "Leader triage"
        case .leaderLocalPass:
            "Leader local pass"
        case .workerWave:
            "Worker wave"
        case .leaderReview:
            "Leader review"
        case .finalSynthesis:
            "Final synthesis"
        case .reconnecting:
            "Reconnecting"
        case .replayingCheckpoint:
            "Replaying checkpoint"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }

    /// Compatibility bridge into the older Agent stage model.
    public var compatibilityStage: AgentStage {
        switch self {
        case .attachmentUpload, .leaderTriage, .leaderLocalPass:
            .leaderBrief
        case .workerWave:
            .workersRoundOne
        case .leaderReview:
            .crossReview
        case .finalSynthesis, .reconnecting, .replayingCheckpoint, .completed, .failed:
            .finalSynthesis
        }
    }

    /// Compatibility bridge into the projected Agent process activity model.
    public var compatibilityActivity: AgentProcessActivity {
        switch self {
        case .attachmentUpload, .leaderTriage:
            .triage
        case .leaderLocalPass:
            .localPass
        case .workerWave:
            .delegation
        case .leaderReview:
            .reviewing
        case .finalSynthesis, .reconnecting, .replayingCheckpoint:
            .synthesis
        case .completed:
            .completed
        case .failed:
            .failed
        }
    }

    /// Whether the persisted phase represents a terminal checkpoint.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            true
        default:
            false
        }
    }

    /// Whether the runtime should attempt automatic recovery for this phase.
    public var supportsAutomaticResume: Bool {
        !isTerminal
    }
}

/// The recovery state currently projected in the Agent Process disclosure.
public enum AgentRecoveryState: String, Codable, CaseIterable, Sendable {
    /// No recovery action is currently active.
    case idle
    /// The runtime is reconnecting to an already-started response.
    case reconnecting
    /// The runtime is replaying work from the latest durable checkpoint.
    case replayingCheckpoint

    /// Human-readable label for live recovery UI.
    public var displayName: String {
        switch self {
        case .idle:
            "Live"
        case .reconnecting:
            "Reconnecting"
        case .replayingCheckpoint:
            "Replaying last checkpoint"
        }
    }
}

/// A compact persisted preview of the leader's live hidden output.
public struct AgentLeaderPreview: Codable, Equatable, Sendable {
    /// Short live status describing what the leader is currently doing.
    public var status: String
    /// Short live summary describing the leader's current progress.
    public var summary: String
    /// Optional compact decision note once the leader has one.
    public var decisionNote: String

    /// Creates a leader preview used for streaming the Agent Process.
    public init(
        status: String = "",
        summary: String = "",
        decisionNote: String = ""
    ) {
        self.status = status
        self.summary = summary
        self.decisionNote = decisionNote
    }
}

/// A resumable ticket for one leader or worker request inside an Agent run.
public struct AgentRunTicket: Codable, Equatable, Sendable {
    /// The hidden participant that owns this response.
    public var role: AgentRole
    /// The phase this ticket belongs to.
    public var phase: AgentRunPhase
    /// The delegated task identifier when this ticket belongs to a worker task.
    public var taskID: String?
    /// The server response identifier, when available.
    public var responseID: String?
    /// The last accepted response identifier used as the replay base for this phase.
    public var checkpointBaseResponseID: String?
    /// The last persisted stream sequence number, when available.
    public var lastSequenceNumber: Int?
    /// Whether this response was started with background support enabled.
    public var backgroundEligible: Bool
    /// Partial tagged output accumulated so far for replay and parsing.
    public var partialOutputText: String
    /// The latest short status projected for the ticket.
    public var statusText: String
    /// The latest short summary projected for the ticket.
    public var summaryText: String
    /// Last-known tool state emitted while this ticket was active.
    public var toolCalls: [ToolCallInfo]
    /// Last update timestamp for the ticket.
    public var updatedAt: Date

    /// Creates a resumable Agent run ticket.
    public init(
        role: AgentRole,
        phase: AgentRunPhase,
        taskID: String? = nil,
        responseID: String? = nil,
        checkpointBaseResponseID: String? = nil,
        lastSequenceNumber: Int? = nil,
        backgroundEligible: Bool,
        partialOutputText: String = "",
        statusText: String = "",
        summaryText: String = "",
        toolCalls: [ToolCallInfo] = [],
        updatedAt: Date = Date()
    ) {
        self.role = role
        self.phase = phase
        self.taskID = taskID
        self.responseID = responseID
        self.checkpointBaseResponseID = checkpointBaseResponseID
        self.lastSequenceNumber = lastSequenceNumber
        self.backgroundEligible = backgroundEligible
        self.partialOutputText = partialOutputText
        self.statusText = statusText
        self.summaryText = summaryText
        self.toolCalls = toolCalls
        self.updatedAt = updatedAt
    }
}

/// Compatibility alias exposing the new Agent checkpoint terminology.
public typealias AgentRunCheckpoint = AgentRunSnapshot
