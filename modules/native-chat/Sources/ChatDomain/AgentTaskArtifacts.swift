import Foundation

/// A leader-proposed follow-up idea returned by a worker.
public struct AgentTaskSuggestion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var goal: String
    public var toolPolicy: AgentToolPolicy

    public init(
        id: String = UUID().uuidString,
        title: String,
        goal: String,
        toolPolicy: AgentToolPolicy
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.toolPolicy = toolPolicy
    }
}

/// The bounded result of one delegated worker task.
public struct AgentTaskResult: Codable, Equatable, Sendable {
    public var summary: String
    public var evidence: [String]
    public var confidence: AgentConfidence
    public var risks: [String]
    public var followUpRecommendations: [AgentTaskSuggestion]
    public var toolCalls: [ToolCallInfo]
    public var citations: [URLCitation]

    public init(
        summary: String,
        evidence: [String] = [],
        confidence: AgentConfidence = .medium,
        risks: [String] = [],
        followUpRecommendations: [AgentTaskSuggestion] = [],
        toolCalls: [ToolCallInfo] = [],
        citations: [URLCitation] = []
    ) {
        self.summary = summary
        self.evidence = evidence
        self.confidence = confidence
        self.risks = risks
        self.followUpRecommendations = followUpRecommendations
        self.toolCalls = toolCalls
        self.citations = citations
    }
}

/// One delegated worker task owned by a specific worker slot.
public struct AgentTask: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var owner: AgentTaskOwner
    public var parentStepID: String?
    public var dependencyIDs: [String]
    public var title: String
    public var goal: String
    public var expectedOutput: String
    public var contextSummary: String
    public var toolPolicy: AgentToolPolicy
    public var status: AgentTaskStatus
    public var resultSummary: String?
    public var result: AgentTaskResult?
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: String = UUID().uuidString,
        owner: AgentTaskOwner,
        parentStepID: String? = nil,
        dependencyIDs: [String] = [],
        title: String,
        goal: String,
        expectedOutput: String,
        contextSummary: String,
        toolPolicy: AgentToolPolicy,
        status: AgentTaskStatus = .queued,
        resultSummary: String? = nil,
        result: AgentTaskResult? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.parentStepID = parentStepID
        self.dependencyIDs = dependencyIDs
        self.title = title
        self.goal = goal
        self.expectedOutput = expectedOutput
        self.contextSummary = contextSummary
        self.toolPolicy = toolPolicy
        self.status = status
        self.resultSummary = resultSummary
        self.result = result
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// A compact leader decision shown in the Agent Process log.
public struct AgentDecision: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var kind: AgentDecisionKind
    public var title: String
    public var summary: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: AgentDecisionKind,
        title: String,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// A low-level event used to drive the projected Agent Process snapshot.
public struct AgentEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var kind: AgentEventKind
    public var summary: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: AgentEventKind,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.createdAt = createdAt
    }
}
