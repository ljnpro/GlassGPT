import Foundation

/// Persisted runtime snapshot for an in-flight Agent run.
public struct AgentRunSnapshot: Codable, Equatable, Sendable {
    /// The current visible stage, if a foreground or background run is underway.
    public var currentStage: AgentStage
    /// The persisted execution phase for the active run.
    public var phase: AgentRunPhase
    /// The draft assistant message being filled by the current run.
    public var draftMessageID: UUID
    /// The latest visible user message that started this run.
    public var latestUserMessageID: UUID
    /// Frozen run configuration captured when the turn began.
    public var runConfiguration: AgentConversationConfiguration
    /// Whether this snapshot carried an explicit frozen run configuration in persisted state.
    public var hasExplicitRunConfiguration: Bool
    /// The latest leader brief, if completed.
    public var leaderBriefSummary: String?
    /// Projected dynamic process state for the live Agent Process disclosure.
    public var processSnapshot: AgentProcessSnapshot
    /// First-pass worker summaries, if completed.
    public var workersRoundOneSummaries: [AgentWorkerSummary]
    /// Cross-review worker summaries, if completed.
    public var crossReviewSummaries: [AgentWorkerSummary]
    /// Worker progress for the first worker round.
    public var workersRoundOneProgress: [AgentWorkerProgress]
    /// Worker progress for cross-review.
    public var crossReviewProgress: [AgentWorkerProgress]
    /// Resumable ticket for the leader's active request, if any.
    public var leaderTicket: AgentRunTicket?
    /// Resumable ticket for worker A, if any.
    public var workerATicket: AgentRunTicket?
    /// Resumable ticket for worker B, if any.
    public var workerBTicket: AgentRunTicket?
    /// Resumable ticket for worker C, if any.
    public var workerCTicket: AgentRunTicket?
    /// Live visible synthesis text accumulated so far.
    public var currentStreamingText: String
    /// Live visible synthesis reasoning accumulated so far.
    public var currentThinkingText: String
    /// Persisted presentation state for the visible final-answer synthesis.
    public var visibleSynthesisPresentation: AgentVisibleSynthesisPresentation?
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
    /// Last durable checkpoint timestamp for the persisted run.
    public var lastCheckpointAt: Date
    /// Last update timestamp for the snapshot payload.
    public var updatedAt: Date

    /// Creates an in-flight run snapshot for Agent recovery and rebinding.
    public init(
        currentStage: AgentStage,
        phase: AgentRunPhase? = nil,
        draftMessageID: UUID,
        latestUserMessageID: UUID,
        runConfiguration: AgentConversationConfiguration = AgentConversationConfiguration(),
        hasExplicitRunConfiguration: Bool = true,
        leaderBriefSummary: String? = nil,
        processSnapshot: AgentProcessSnapshot = AgentProcessSnapshot(),
        workersRoundOneSummaries: [AgentWorkerSummary] = [],
        crossReviewSummaries: [AgentWorkerSummary] = [],
        workersRoundOneProgress: [AgentWorkerProgress] = AgentWorkerProgress.defaultProgress,
        crossReviewProgress: [AgentWorkerProgress] = AgentWorkerProgress.defaultProgress,
        leaderTicket: AgentRunTicket? = nil,
        workerATicket: AgentRunTicket? = nil,
        workerBTicket: AgentRunTicket? = nil,
        workerCTicket: AgentRunTicket? = nil,
        currentStreamingText: String = "",
        currentThinkingText: String = "",
        visibleSynthesisPresentation: AgentVisibleSynthesisPresentation? = nil,
        activeToolCalls: [ToolCallInfo] = [],
        liveCitations: [URLCitation] = [],
        liveFilePathAnnotations: [FilePathAnnotation] = [],
        isStreaming: Bool = false,
        isThinking: Bool = false,
        lastCheckpointAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let resolvedPhase = phase ?? Self.compatibilityPhase(
            from: currentStage,
            isStreaming: isStreaming,
            currentStreamingText: currentStreamingText
        )
        let resolvedProcessSnapshot = Self.resolvedProcessSnapshot(
            from: processSnapshot,
            leaderBriefSummary: leaderBriefSummary,
            phase: resolvedPhase
        )

        self.currentStage = currentStage
        self.phase = resolvedPhase
        self.draftMessageID = draftMessageID
        self.latestUserMessageID = latestUserMessageID
        self.runConfiguration = runConfiguration
        self.hasExplicitRunConfiguration = hasExplicitRunConfiguration
        self.leaderBriefSummary = leaderBriefSummary
        self.processSnapshot = resolvedProcessSnapshot
        self.workersRoundOneSummaries = workersRoundOneSummaries
        self.crossReviewSummaries = crossReviewSummaries
        self.workersRoundOneProgress = workersRoundOneProgress
        self.crossReviewProgress = crossReviewProgress
        self.leaderTicket = leaderTicket
        self.workerATicket = workerATicket
        self.workerBTicket = workerBTicket
        self.workerCTicket = workerCTicket
        self.currentStreamingText = currentStreamingText
        self.currentThinkingText = currentThinkingText
        self.visibleSynthesisPresentation = visibleSynthesisPresentation
        self.activeToolCalls = activeToolCalls
        self.liveCitations = liveCitations
        self.liveFilePathAnnotations = liveFilePathAnnotations
        self.isStreaming = isStreaming
        self.isThinking = isThinking
        self.lastCheckpointAt = lastCheckpointAt
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
}
