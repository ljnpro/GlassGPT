import Foundation

private enum AgentRunSnapshotCodingKeys: String, CodingKey {
    case currentStage
    case phase
    case draftMessageID
    case latestUserMessageID
    case runConfiguration
    case leaderBriefSummary
    case processSnapshot
    case workersRoundOneSummaries
    case crossReviewSummaries
    case workersRoundOneProgress
    case crossReviewProgress
    case leaderTicket
    case workerATicket
    case workerBTicket
    case workerCTicket
    case currentStreamingText
    case currentThinkingText
    case activeToolCalls
    case liveCitations
    case liveFilePathAnnotations
    case isStreaming
    case isThinking
    case lastCheckpointAt
    case updatedAt
}

public extension AgentRunSnapshot {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AgentRunSnapshotCodingKeys.self)
        currentStage = try container.decode(AgentStage.self, forKey: .currentStage)
        phase = try container.decodeIfPresent(AgentRunPhase.self, forKey: .phase)
            ?? Self.compatibilityPhase(from: currentStage)
        draftMessageID = try container.decode(UUID.self, forKey: .draftMessageID)
        latestUserMessageID = try container.decode(UUID.self, forKey: .latestUserMessageID)
        let decodedRunConfiguration = try container.decodeIfPresent(
            AgentConversationConfiguration.self,
            forKey: .runConfiguration
        )
        runConfiguration = decodedRunConfiguration ?? AgentConversationConfiguration()
        hasExplicitRunConfiguration = container.contains(.runConfiguration)
        leaderBriefSummary = try container.decodeIfPresent(String.self, forKey: .leaderBriefSummary)
        processSnapshot = try Self.decodeProcessSnapshot(
            from: container,
            phase: phase,
            leaderBriefSummary: leaderBriefSummary
        )
        workersRoundOneSummaries = try container.decodeIfPresent(
            [AgentWorkerSummary].self,
            forKey: .workersRoundOneSummaries
        ) ?? []
        crossReviewSummaries = try container.decodeIfPresent(
            [AgentWorkerSummary].self,
            forKey: .crossReviewSummaries
        ) ?? []
        workersRoundOneProgress = try container.decodeIfPresent(
            [AgentWorkerProgress].self,
            forKey: .workersRoundOneProgress
        ) ?? AgentWorkerProgress.defaultProgress
        crossReviewProgress = try container.decodeIfPresent(
            [AgentWorkerProgress].self,
            forKey: .crossReviewProgress
        ) ?? AgentWorkerProgress.defaultProgress
        leaderTicket = try container.decodeIfPresent(AgentRunTicket.self, forKey: .leaderTicket)
        workerATicket = try container.decodeIfPresent(AgentRunTicket.self, forKey: .workerATicket)
        workerBTicket = try container.decodeIfPresent(AgentRunTicket.self, forKey: .workerBTicket)
        workerCTicket = try container.decodeIfPresent(AgentRunTicket.self, forKey: .workerCTicket)
        currentStreamingText = try container.decodeIfPresent(String.self, forKey: .currentStreamingText) ?? ""
        currentThinkingText = try container.decodeIfPresent(String.self, forKey: .currentThinkingText) ?? ""
        activeToolCalls = try container.decodeIfPresent([ToolCallInfo].self, forKey: .activeToolCalls) ?? []
        liveCitations = try container.decodeIfPresent([URLCitation].self, forKey: .liveCitations) ?? []
        liveFilePathAnnotations = try container.decodeIfPresent(
            [FilePathAnnotation].self,
            forKey: .liveFilePathAnnotations
        ) ?? []
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking) ?? false
        lastCheckpointAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckpointAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AgentRunSnapshotCodingKeys.self)
        try container.encode(currentStage, forKey: .currentStage)
        try container.encode(phase, forKey: .phase)
        try container.encode(draftMessageID, forKey: .draftMessageID)
        try container.encode(latestUserMessageID, forKey: .latestUserMessageID)
        try container.encode(runConfiguration, forKey: .runConfiguration)
        try container.encodeIfPresent(leaderBriefSummary, forKey: .leaderBriefSummary)
        try container.encode(processSnapshot, forKey: .processSnapshot)
        try container.encode(workersRoundOneSummaries, forKey: .workersRoundOneSummaries)
        try container.encode(crossReviewSummaries, forKey: .crossReviewSummaries)
        try container.encode(workersRoundOneProgress, forKey: .workersRoundOneProgress)
        try container.encode(crossReviewProgress, forKey: .crossReviewProgress)
        try container.encodeIfPresent(leaderTicket, forKey: .leaderTicket)
        try container.encodeIfPresent(workerATicket, forKey: .workerATicket)
        try container.encodeIfPresent(workerBTicket, forKey: .workerBTicket)
        try container.encodeIfPresent(workerCTicket, forKey: .workerCTicket)
        try container.encode(currentStreamingText, forKey: .currentStreamingText)
        try container.encode(currentThinkingText, forKey: .currentThinkingText)
        try container.encode(activeToolCalls, forKey: .activeToolCalls)
        try container.encode(liveCitations, forKey: .liveCitations)
        try container.encode(liveFilePathAnnotations, forKey: .liveFilePathAnnotations)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(isThinking, forKey: .isThinking)
        try container.encode(lastCheckpointAt, forKey: .lastCheckpointAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    func ticket(for role: AgentRole) -> AgentRunTicket? {
        switch role {
        case .leader:
            leaderTicket
        case .workerA:
            workerATicket
        case .workerB:
            workerBTicket
        case .workerC:
            workerCTicket
        }
    }

    mutating func setTicket(_ ticket: AgentRunTicket?, for role: AgentRole) {
        switch role {
        case .leader:
            leaderTicket = ticket
        case .workerA:
            workerATicket = ticket
        case .workerB:
            workerBTicket = ticket
        case .workerC:
            workerCTicket = ticket
        }
        lastCheckpointAt = Date()
        updatedAt = Date()
    }

    internal static func compatibilityPhase(
        from stage: AgentStage,
        isStreaming: Bool = false,
        currentStreamingText: String = ""
    ) -> AgentRunPhase {
        switch stage {
        case .leaderBrief:
            .leaderTriage
        case .workersRoundOne:
            .workerWave
        case .crossReview:
            .leaderReview
        case .finalSynthesis:
            if isStreaming || !currentStreamingText.isEmpty {
                .finalSynthesis
            } else {
                .reconnecting
            }
        }
    }

    private static func decodeProcessSnapshot(
        from container: KeyedDecodingContainer<AgentRunSnapshotCodingKeys>,
        phase: AgentRunPhase,
        leaderBriefSummary: String?
    ) throws -> AgentProcessSnapshot {
        var snapshot = try container.decodeIfPresent(
            AgentProcessSnapshot.self,
            forKey: .processSnapshot
        ) ?? AgentProcessSnapshot(
            activity: phase.compatibilityActivity,
            currentFocus: leaderBriefSummary ?? "",
            leaderAcceptedFocus: leaderBriefSummary ?? "",
            leaderLiveStatus: phase.displayName,
            leaderLiveSummary: leaderBriefSummary ?? ""
        )
        if snapshot.leaderAcceptedFocus.isEmpty {
            snapshot.leaderAcceptedFocus = snapshot.currentFocus
        }
        return snapshot
    }
}
