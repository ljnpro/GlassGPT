import Foundation

/// Persisted runtime snapshot for an in-flight Agent run.
public struct AgentRunSnapshot: Codable, Equatable, Sendable {
    /// The current visible stage, if a foreground or background run is underway.
    public var currentStage: AgentStage
    /// The draft assistant message being filled by the current run.
    public var draftMessageID: UUID
    /// The latest visible user message that started this run.
    public var latestUserMessageID: UUID
    /// The latest leader brief, if completed.
    public var leaderBriefSummary: String?
    /// First-pass worker summaries, if completed.
    public var workersRoundOneSummaries: [AgentWorkerSummary]
    /// Cross-review worker summaries, if completed.
    public var crossReviewSummaries: [AgentWorkerSummary]
    /// Worker progress for the first worker round.
    public var workersRoundOneProgress: [AgentWorkerProgress]
    /// Worker progress for cross-review.
    public var crossReviewProgress: [AgentWorkerProgress]
    /// Live visible synthesis text accumulated so far.
    public var currentStreamingText: String
    /// Live visible synthesis reasoning accumulated so far.
    public var currentThinkingText: String
    /// Active tool calls during visible synthesis.
    public var activeToolCalls: [ToolCallInfo]
    /// Live citations gathered during visible synthesis.
    public var liveCitations: [URLCitation]
    /// Live file annotations gathered during visible synthesis.
    public var liveFilePathAnnotations: [FilePathAnnotation]
    /// Whether the visible synthesis is actively streaming.
    public var isStreaming: Bool
    /// Whether the visible synthesis is actively reasoning.
    public var isThinking: Bool
    /// Last update timestamp for the snapshot payload.
    public var updatedAt: Date

    /// Creates an in-flight run snapshot for Agent recovery and rebinding.
    public init(
        currentStage: AgentStage,
        draftMessageID: UUID,
        latestUserMessageID: UUID,
        leaderBriefSummary: String? = nil,
        workersRoundOneSummaries: [AgentWorkerSummary] = [],
        crossReviewSummaries: [AgentWorkerSummary] = [],
        workersRoundOneProgress: [AgentWorkerProgress] = AgentWorkerProgress.defaultProgress,
        crossReviewProgress: [AgentWorkerProgress] = AgentWorkerProgress.defaultProgress,
        currentStreamingText: String = "",
        currentThinkingText: String = "",
        activeToolCalls: [ToolCallInfo] = [],
        liveCitations: [URLCitation] = [],
        liveFilePathAnnotations: [FilePathAnnotation] = [],
        isStreaming: Bool = false,
        isThinking: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.currentStage = currentStage
        self.draftMessageID = draftMessageID
        self.latestUserMessageID = latestUserMessageID
        self.leaderBriefSummary = leaderBriefSummary
        self.workersRoundOneSummaries = workersRoundOneSummaries
        self.crossReviewSummaries = crossReviewSummaries
        self.workersRoundOneProgress = workersRoundOneProgress
        self.crossReviewProgress = crossReviewProgress
        self.currentStreamingText = currentStreamingText
        self.currentThinkingText = currentThinkingText
        self.activeToolCalls = activeToolCalls
        self.liveCitations = liveCitations
        self.liveFilePathAnnotations = liveFilePathAnnotations
        self.isStreaming = isStreaming
        self.isThinking = isThinking
        self.updatedAt = updatedAt
    }
}

/// The persisted hidden state for one Agent conversation.
public struct AgentConversationState: Codable, Equatable, Sendable {
    /// The leader chain response identifier.
    public var leaderResponseID: String?
    /// Worker A chain response identifier.
    public var workerAResponseID: String?
    /// Worker B chain response identifier.
    public var workerBResponseID: String?
    /// Worker C chain response identifier.
    public var workerCResponseID: String?
    /// The currently active stage, if a foreground run is underway.
    public var currentStage: AgentStage?
    /// The user-configurable Agent settings for this conversation.
    public var configuration: AgentConversationConfiguration
    /// Persisted state for an active in-flight Agent run, if any.
    public var activeRun: AgentRunSnapshot?
    /// Last update timestamp for the hidden state payload.
    public var updatedAt: Date

    /// Creates persisted hidden state for one Agent conversation and its per-role response chains.
    public init(
        leaderResponseID: String? = nil,
        workerAResponseID: String? = nil,
        workerBResponseID: String? = nil,
        workerCResponseID: String? = nil,
        currentStage: AgentStage? = nil,
        configuration: AgentConversationConfiguration = AgentConversationConfiguration(),
        activeRun: AgentRunSnapshot? = nil,
        updatedAt: Date = Date()
    ) {
        self.leaderResponseID = leaderResponseID
        self.workerAResponseID = workerAResponseID
        self.workerBResponseID = workerBResponseID
        self.workerCResponseID = workerCResponseID
        self.currentStage = currentStage
        self.configuration = configuration
        self.activeRun = activeRun
        self.updatedAt = updatedAt
    }

    /// Returns the current response identifier for the given internal role.
    public func responseID(for role: AgentRole) -> String? {
        switch role {
        case .leader:
            leaderResponseID
        case .workerA:
            workerAResponseID
        case .workerB:
            workerBResponseID
        case .workerC:
            workerCResponseID
        }
    }

    /// Updates the response identifier for the given role.
    public mutating func setResponseID(
        _ responseID: String?,
        for role: AgentRole,
        updatedAt: Date = Date()
    ) {
        switch role {
        case .leader:
            leaderResponseID = responseID
        case .workerA:
            workerAResponseID = responseID
        case .workerB:
            workerBResponseID = responseID
        case .workerC:
            workerCResponseID = responseID
        }
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case leaderResponseID
        case workerAResponseID
        case workerBResponseID
        case workerCResponseID
        case currentStage
        case configuration
        case activeRun
        case updatedAt
    }

    /// Decodes Agent state while preserving compatibility with 4.12.0 payloads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leaderResponseID = try container.decodeIfPresent(String.self, forKey: .leaderResponseID)
        workerAResponseID = try container.decodeIfPresent(String.self, forKey: .workerAResponseID)
        workerBResponseID = try container.decodeIfPresent(String.self, forKey: .workerBResponseID)
        workerCResponseID = try container.decodeIfPresent(String.self, forKey: .workerCResponseID)
        currentStage = try container.decodeIfPresent(AgentStage.self, forKey: .currentStage)
        configuration = try container.decodeIfPresent(
            AgentConversationConfiguration.self,
            forKey: .configuration
        ) ?? AgentConversationConfiguration()
        activeRun = try container.decodeIfPresent(AgentRunSnapshot.self, forKey: .activeRun)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
