import Foundation

private enum AgentConversationStateCodingKeys: String, CodingKey {
    case leaderResponseID
    case workerAResponseID
    case workerBResponseID
    case workerCResponseID
    case currentStage
    case configuration
    case activeRun
    case updatedAt
}

public extension AgentConversationState {
    func responseID(for role: AgentRole) -> String? {
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

    mutating func setResponseID(
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

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AgentConversationStateCodingKeys.self)
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
        activeRun = Self.normalizedActiveRun(activeRun, configuration: configuration)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AgentConversationStateCodingKeys.self)
        try container.encodeIfPresent(leaderResponseID, forKey: .leaderResponseID)
        try container.encodeIfPresent(workerAResponseID, forKey: .workerAResponseID)
        try container.encodeIfPresent(workerBResponseID, forKey: .workerBResponseID)
        try container.encodeIfPresent(workerCResponseID, forKey: .workerCResponseID)
        try container.encodeIfPresent(currentStage, forKey: .currentStage)
        try container.encode(configuration, forKey: .configuration)
        try container.encodeIfPresent(activeRun, forKey: .activeRun)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func normalizedActiveRun(
        _ snapshot: AgentRunSnapshot?,
        configuration: AgentConversationConfiguration
    ) -> AgentRunSnapshot? {
        guard var snapshot else { return nil }
        if !snapshot.hasExplicitRunConfiguration {
            snapshot.runConfiguration = configuration
            snapshot.hasExplicitRunConfiguration = true
        }
        if snapshot.processSnapshot.currentFocus.isEmpty,
           let leaderBrief = snapshot.leaderBriefSummary,
           !leaderBrief.isEmpty {
            snapshot.processSnapshot.currentFocus = leaderBrief
            snapshot.processSnapshot.leaderAcceptedFocus = leaderBrief
        }
        return snapshot
    }
}
