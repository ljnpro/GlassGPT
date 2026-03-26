import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

struct AgentLeaderPlanningResult {
    let directive: AgentTaggedOutputParser.LeaderDirective
    let responseID: String
}

@MainActor
final class AgentPlanningEngine {
    enum PlanningPhase {
        case triage
        case localPass
        case review(snapshot: AgentProcessSnapshot, completedTasks: [AgentTask])

        var runPhase: AgentRunPhase {
            switch self {
            case .triage:
                .leaderTriage
            case .localPass:
                .leaderLocalPass
            case .review:
                .leaderReview
            }
        }

        var processActivity: AgentProcessActivity {
            switch self {
            case .triage:
                .triage
            case .localPass:
                .localPass
            case .review:
                .reviewing
            }
        }

        var bootstrapStatus: String {
            switch self {
            case .triage:
                "Scoping the request"
            case .localPass:
                "Refining task briefs"
            case .review:
                "Reviewing worker results"
            }
        }

        var bootstrapSummary: String {
            switch self {
            case .triage:
                "Classifying the request and shaping the first plan."
            case .localPass:
                "Doing a short local pass before delegation."
            case .review:
                "Reviewing worker results and deciding the next move."
            }
        }

        var milestoneSummary: String {
            switch self {
            case .triage:
                "Leader began triage."
            case .localPass:
                "Leader started the local pass."
            case .review:
                "Leader began review."
            }
        }
    }

    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func streamPlanningPhase(
        _ phase: PlanningPhase,
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        baseInput: [ResponsesInputMessageDTO],
        previousResponseIDOverride: String? = nil,
        fallbackToConversationLeaderChain: Bool = true
    ) -> AsyncStream<StreamEvent> {
        let input: [ResponsesInputMessageDTO]
        let instructions: String

        switch phase {
        case .triage:
            input = AgentPromptBuilder.triageInput(baseInput: baseInput)
            instructions = AgentPromptBuilder.leaderTriageInstructions()
        case .localPass:
            input = AgentPromptBuilder.leaderLocalPassInput(
                baseInput: baseInput,
                snapshot: conversation.agentConversationState?.activeRun?.processSnapshot ?? AgentProcessSnapshot()
            )
            instructions = AgentPromptBuilder.leaderLocalPassInstructions()
        case let .review(snapshot, completedTasks):
            input = AgentPromptBuilder.leaderReviewInput(
                baseInput: baseInput,
                snapshot: snapshot,
                completedTasks: completedTasks
            )
            instructions = AgentPromptBuilder.leaderReviewInstructions()
        }

        let previousResponseID = previousResponseIDOverride
            ?? (fallbackToConversationLeaderChain
                ? conversation.agentConversationState?.responseID(for: .leader)
                : nil)

        return state.serviceFactory().streamResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: input,
            instructions: instructions,
            previousResponseID: previousResponseID,
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: OpenAIRequestFactory.defaultChatTools(),
            background: configuration.backgroundModeEnabled
        )
    }

    func parsePlanningResult(
        from text: String,
        responseID: String
    ) -> AgentLeaderPlanningResult {
        AgentLeaderPlanningResult(
            directive: AgentTaggedOutputParser.parseLeaderDirective(from: text),
            responseID: responseID
        )
    }
}
