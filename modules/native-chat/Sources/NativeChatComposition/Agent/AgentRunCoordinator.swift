import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

enum AgentRunFailure: Error {
    case cancelled
    case missingConversation
    case missingDraft
    case invalidResponse(String)
    case incomplete(String)

    var userMessage: String {
        switch self {
        case .cancelled:
            "Agent run stopped."
        case .missingConversation:
            "Agent conversation is unavailable."
        case .missingDraft:
            "Agent draft reply is unavailable."
        case let .invalidResponse(message):
            message
        case let .incomplete(message):
            message
        }
    }
}

/// Per-worker progress state rendered in the Agent progress card.
package struct AgentWorkerProgress: Equatable, Identifiable {
    /// The worker role represented by this progress item.
    package let role: AgentRole
    /// The current execution status for the worker role.
    package var status: Status

    /// Supported worker progress states for the council pipeline.
    package enum Status: String, Equatable {
        case waiting
        case running
        case completed
        case failed
    }

    /// Stable identifier derived from the worker role.
    package var id: AgentRole {
        role
    }

    package static let defaultProgress: [AgentWorkerProgress] = [
        AgentWorkerProgress(role: .workerA, status: .waiting),
        AgentWorkerProgress(role: .workerB, status: .waiting),
        AgentWorkerProgress(role: .workerC, status: .waiting)
    ]
}

struct HiddenWorkerRound {
    let role: AgentRole
    let summary: String
}

struct HiddenWorkerRevision {
    let role: AgentRole
    let summary: String
    let adoptedPoints: [String]
}

@MainActor
final class AgentRunCoordinator {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func startTurn(_ prepared: PreparedAgentTurn) {
        state.cancelActiveRun()
        let visibleStreamService = state.serviceFactory()
        state.visibleStreamService = visibleStreamService
        state.activeRunTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await executeTurn(prepared, visibleStreamService: visibleStreamService)
        }
    }

    func executeTurn(
        _ prepared: PreparedAgentTurn,
        visibleStreamService: OpenAIService
    ) async {
        guard let conversation = state.currentConversation else {
            finishWithFailure(.missingConversation)
            return
        }

        do {
            let baseInput = AgentPromptBuilder.visibleConversationInput(from: conversation.messages)
            let leaderBrief = try await runLeaderBrief(
                apiKey: prepared.apiKey,
                baseInput: baseInput
            )
            updateStage(.workersRoundOne)
            let firstRound = try await runWorkerRoundOne(
                apiKey: prepared.apiKey,
                latestUserText: prepared.latestUserText,
                leaderBrief: leaderBrief
            )
            updateStage(.crossReview)
            let revised = try await runCrossReview(
                apiKey: prepared.apiKey,
                latestUserText: prepared.latestUserText,
                firstRound: firstRound
            )
            updateStage(.finalSynthesis)
            try await runVisibleLeaderSynthesis(
                apiKey: prepared.apiKey,
                latestUserText: prepared.latestUserText,
                leaderBrief: leaderBrief,
                revisedWorkers: revised,
                service: visibleStreamService
            )
            try finalizeSuccessfulTurn(
                leaderBrief: leaderBrief,
                revisedWorkers: revised
            )
        } catch is CancellationError {
            finishWithFailure(.cancelled)
        } catch let failure as AgentRunFailure {
            finishWithFailure(failure)
        } catch let serviceError as OpenAIServiceError {
            finishWithFailure(.invalidResponse(serviceError.localizedDescription))
        } catch {
            finishWithFailure(.invalidResponse(error.localizedDescription))
        }
    }
}
