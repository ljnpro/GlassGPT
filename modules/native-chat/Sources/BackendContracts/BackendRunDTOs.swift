import Foundation

/// Whether a run is a simple chat completion or an agent execution.
public enum RunKindDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case chat
    case agent
}

/// The lifecycle status of a run.
public enum RunStatusDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

/// The current execution stage of an agent run.
public enum AgentStageDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case leaderPlanning = "leader_planning"
    case workerWave = "worker_wave"
    case leaderReview = "leader_review"
    case finalSynthesis = "final_synthesis"
}

/// A summary of a run's current state returned by the backend.
public struct RunSummaryDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let kind: RunKindDTO
    public let status: RunStatusDTO
    public let stage: AgentStageDTO?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastEventCursor: String?
    public let visibleSummary: String?
    public let processSnapshotJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversationId"
        case kind
        case status
        case stage
        case createdAt
        case updatedAt
        case lastEventCursor
        case visibleSummary
        case processSnapshotJSON
    }

    /// Creates a run summary DTO with the given fields.
    public init(
        id: String,
        conversationID: String,
        kind: RunKindDTO,
        status: RunStatusDTO,
        stage: AgentStageDTO?,
        createdAt: Date,
        updatedAt: Date,
        lastEventCursor: String?,
        visibleSummary: String?,
        processSnapshotJSON: String?
    ) {
        self.id = id
        self.conversationID = conversationID
        self.kind = kind
        self.status = status
        self.stage = stage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEventCursor = lastEventCursor
        self.visibleSummary = visibleSummary
        self.processSnapshotJSON = processSnapshotJSON
    }
}

/// The type of event emitted during a run's lifecycle.
public enum RunEventKindDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case messageCreated = "message_created"
    case runQueued = "run_queued"
    case runStarted = "run_started"
    case runProgress = "run_progress"
    case assistantDelta = "assistant_delta"
    case assistantCompleted = "assistant_completed"
    case stageChanged = "stage_changed"
    case artifactCreated = "artifact_created"
    case runCompleted = "run_completed"
    case runFailed = "run_failed"
    case runCancelled = "run_cancelled"
}

/// A single event produced during a run, used for real-time streaming and sync.
public struct RunEventDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let cursor: String
    public let runID: String
    public let conversationID: String
    public let kind: RunEventKindDTO
    public let createdAt: Date
    public let textDelta: String?
    public let progressLabel: String?
    public let stage: AgentStageDTO?
    public let artifactID: String?
    public let conversation: ConversationDTO?
    public let message: MessageDTO?
    public let run: RunSummaryDTO?
    public let artifact: ArtifactDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case cursor
        case runID = "runId"
        case conversationID = "conversationId"
        case kind
        case createdAt
        case textDelta
        case progressLabel
        case stage
        case artifactID = "artifactId"
        case conversation
        case message
        case run
        case artifact
    }

    /// Creates a run event DTO with the given fields.
    public init(
        id: String,
        cursor: String,
        runID: String,
        conversationID: String,
        kind: RunEventKindDTO,
        createdAt: Date,
        textDelta: String?,
        progressLabel: String?,
        stage: AgentStageDTO?,
        artifactID: String?,
        conversation: ConversationDTO?,
        message: MessageDTO?,
        run: RunSummaryDTO?,
        artifact: ArtifactDTO?
    ) {
        self.id = id
        self.cursor = cursor
        self.runID = runID
        self.conversationID = conversationID
        self.kind = kind
        self.createdAt = createdAt
        self.textDelta = textDelta
        self.progressLabel = progressLabel
        self.stage = stage
        self.artifactID = artifactID
        self.conversation = conversation
        self.message = message
        self.run = run
        self.artifact = artifact
    }
}

/// Request body for starting an agent run within a conversation.
public struct StartAgentRunRequestDTO: Codable, Equatable, Sendable {
    public let prompt: String?

    /// Creates an agent run request with an optional prompt.
    public init(prompt: String?) {
        self.prompt = prompt
    }
}
