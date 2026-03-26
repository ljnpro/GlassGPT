import Foundation

/// The bounded result of one delegated worker task.
public struct AgentTaskResult: Codable, Equatable, Sendable {
    /// Compact result summary returned by the worker.
    public var summary: String
    /// Evidence items the worker believes support the summary.
    public var evidence: [String]
    /// Confidence level reported for the result.
    public var confidence: AgentConfidence
    /// Open risks or caveats the leader should consider.
    public var risks: [String]
    /// Recommended follow-up tasks suggested by the worker.
    public var followUpRecommendations: [AgentTaskSuggestion]
    /// Tool calls performed while completing the task.
    public var toolCalls: [ToolCallInfo]
    /// Citations gathered while completing the task.
    public var citations: [URLCitation]

    /// Creates a structured worker-task result.
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
