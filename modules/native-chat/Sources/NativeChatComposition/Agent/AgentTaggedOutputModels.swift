import ChatDomain
import Foundation

extension AgentTaggedOutputParser {
    enum LeaderDecision: String, Equatable {
        case delegate
        case finish
        case clarify
    }

    struct LeaderDirective: Equatable {
        let focus: String
        let decision: LeaderDecision
        let plan: [AgentPlanStep]
        let tasks: [AgentTask]
        let decisionNote: String
        let stopReason: String?
    }

    struct LeaderDirectivePreview: Equatable {
        let status: String?
        let focus: String?
        let decisionNote: String?
        let plan: [AgentPlanStep]
        let tasks: [AgentTask]
    }

    struct WorkerRevision: Equatable {
        let summary: String
        let adoptedPoints: [String]
    }

    struct WorkerTaskResult: Equatable {
        let summary: String
        let evidence: [String]
        let confidence: AgentConfidence
        let risks: [String]
        let followUps: [AgentTaskSuggestion]
    }

    struct WorkerTaskPreview: Equatable {
        let status: String?
        let summary: String?
        let evidence: [String]
        let confidence: AgentConfidence?
        let risks: [String]
    }
}
