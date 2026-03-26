import Foundation

/// One delegated worker task owned by a specific worker slot.
public struct AgentTask: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier for the delegated task.
    public let id: String
    /// Worker slot currently responsible for the task.
    public var owner: AgentTaskOwner
    /// Parent plan-step identifier, when the task belongs to a step.
    public var parentStepID: String?
    /// Other task identifiers that must complete first.
    public var dependencyIDs: [String]
    /// Short task title shown in the process UI.
    public var title: String
    /// Goal the worker is expected to accomplish.
    public var goal: String
    /// Output contract the worker was asked to satisfy.
    public var expectedOutput: String
    /// Leader-provided context summary for the task.
    public var contextSummary: String
    /// Whether this task may use tools or must remain reasoning-only.
    public var toolPolicy: AgentToolPolicy
    /// Current lifecycle status for the task.
    public var status: AgentTaskStatus
    /// Persisted one-line summary for completed tasks.
    public var resultSummary: String?
    /// Structured result payload for completed tasks.
    public var result: AgentTaskResult?
    /// Live status text projected while the worker stream is active.
    public var liveStatusText: String?
    /// Live summary text projected while the worker stream is active.
    public var liveSummary: String?
    /// Live evidence items projected while the worker stream is active.
    public var liveEvidence: [String]
    /// Live confidence projected while the worker stream is active.
    public var liveConfidence: AgentConfidence?
    /// Live risks projected while the worker stream is active.
    public var liveRisks: [String]
    /// Start timestamp for the task, when known.
    public var startedAt: Date?
    /// Completion timestamp for the task, when known.
    public var completedAt: Date?

    /// Creates a delegated worker task tracked by the Agent runtime.
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
        liveStatusText: String? = nil,
        liveSummary: String? = nil,
        liveEvidence: [String] = [],
        liveConfidence: AgentConfidence? = nil,
        liveRisks: [String] = [],
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
        self.liveStatusText = liveStatusText
        self.liveSummary = liveSummary
        self.liveEvidence = liveEvidence
        self.liveConfidence = liveConfidence
        self.liveRisks = liveRisks
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case owner
        case parentStepID
        case dependencyIDs
        case title
        case goal
        case expectedOutput
        case contextSummary
        case toolPolicy
        case status
        case resultSummary
        case result
        case liveStatusText
        case liveSummary
        case liveEvidence
        case liveConfidence
        case liveRisks
        case startedAt
        case completedAt
    }

    /// Decodes a delegated task while backfilling newer live-summary fields when absent.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decode(AgentTaskOwner.self, forKey: .owner)
        parentStepID = try container.decodeIfPresent(String.self, forKey: .parentStepID)
        dependencyIDs = try container.decodeIfPresent([String].self, forKey: .dependencyIDs) ?? []
        title = try container.decode(String.self, forKey: .title)
        goal = try container.decode(String.self, forKey: .goal)
        expectedOutput = try container.decode(String.self, forKey: .expectedOutput)
        contextSummary = try container.decode(String.self, forKey: .contextSummary)
        toolPolicy = try container.decode(AgentToolPolicy.self, forKey: .toolPolicy)
        status = try container.decode(AgentTaskStatus.self, forKey: .status)
        resultSummary = try container.decodeIfPresent(String.self, forKey: .resultSummary)
        result = try container.decodeIfPresent(AgentTaskResult.self, forKey: .result)
        liveStatusText = try container.decodeIfPresent(String.self, forKey: .liveStatusText)
        liveSummary = try container.decodeIfPresent(String.self, forKey: .liveSummary)
        liveEvidence = try container.decodeIfPresent([String].self, forKey: .liveEvidence) ?? []
        liveConfidence = try container.decodeIfPresent(AgentConfidence.self, forKey: .liveConfidence)
        liveRisks = try container.decodeIfPresent([String].self, forKey: .liveRisks) ?? []
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    /// Best available worker status text for live or completed display.
    public var displayStatusText: String {
        let trimmed = liveStatusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? status.displayName : trimmed
    }

    /// Best available worker summary for live or completed display.
    public var displaySummary: String {
        let live = liveSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !live.isEmpty {
            return live
        }

        let persisted = result?.summary
            ?? resultSummary
            ?? goal
        return persisted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best available evidence list for live or completed display.
    public var displayEvidence: [String] {
        if !liveEvidence.isEmpty {
            return liveEvidence
        }
        return result?.evidence ?? []
    }

    /// Best available worker confidence for live or completed display.
    public var displayConfidence: AgentConfidence? {
        liveConfidence ?? result?.confidence
    }

    /// Best available risk list for live or completed display.
    public var displayRisks: [String] {
        if !liveRisks.isEmpty {
            return liveRisks
        }
        return result?.risks ?? []
    }
}
