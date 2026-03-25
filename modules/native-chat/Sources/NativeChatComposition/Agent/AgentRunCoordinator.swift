import ChatDomain
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
        let snapshot = prepared.conversation.agentConversationState?.activeRun ?? AgentRunSnapshot(
            currentStage: .leaderBrief,
            draftMessageID: prepared.draft.id,
            latestUserMessageID: prepared.userMessageID
        )
        startExecution(
            prepared,
            snapshot: snapshot,
            service: state.serviceFactory()
        )
    }

    func executeTurn(
        _ prepared: PreparedAgentTurn,
        execution: AgentExecutionState
    ) async {
        do {
            let baseInput = AgentPromptBuilder.visibleConversationInput(from: prepared.conversation.messages)
            let leaderBrief = try await resolveLeaderBrief(
                for: prepared,
                execution: execution,
                baseInput: baseInput
            )
            let firstRound = try await resolveWorkerRoundOne(
                for: prepared,
                execution: execution,
                leaderBrief: leaderBrief
            )
            let revised = try await resolveCrossReview(
                for: prepared,
                execution: execution,
                firstRound: firstRound
            )
            try await resolveVisibleLeaderSynthesis(
                for: prepared,
                execution: execution,
                leaderBrief: leaderBrief,
                revisedWorkers: revised
            )
            try finalizeSuccessfulTurn(
                leaderBrief: leaderBrief,
                revisedWorkers: revised,
                prepared: prepared,
                execution: execution
            )
        } catch is CancellationError {
            finishWithFailure(.cancelled, prepared: prepared, execution: execution)
        } catch let failure as AgentRunFailure {
            finishWithFailure(failure, prepared: prepared, execution: execution)
        } catch let serviceError as OpenAIServiceError {
            finishWithFailure(
                .invalidResponse(serviceError.localizedDescription),
                prepared: prepared,
                execution: execution
            )
        } catch {
            finishWithFailure(
                .invalidResponse(error.localizedDescription),
                prepared: prepared,
                execution: execution
            )
        }
    }

    func startExecution(
        _ prepared: PreparedAgentTurn,
        snapshot: AgentRunSnapshot,
        service: OpenAIService
    ) {
        let execution = AgentExecutionState(
            conversationID: prepared.conversation.id,
            draftMessageID: prepared.draft.id,
            latestUserMessageID: prepared.userMessageID,
            apiKey: prepared.apiKey,
            service: service,
            snapshot: snapshot
        )
        state.sessionRegistry.register(
            execution,
            visible: state.currentConversation?.id == prepared.conversation.id
        )
        syncVisibleStateIfNeeded(execution, in: prepared.conversation)
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            await executeTurn(prepared, execution: execution)
        }
    }

    private func resolveLeaderBrief(
        for prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> String {
        if execution.snapshot.currentStage != .leaderBrief,
           let persisted = execution.snapshot.leaderBriefSummary,
           !persisted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return persisted
        }

        return try await runLeaderBrief(
            apiKey: prepared.apiKey,
            configuration: prepared.configuration,
            conversation: prepared.conversation,
            execution: execution,
            baseInput: baseInput
        )
    }

    private func resolveWorkerRoundOne(
        for prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        leaderBrief: String
    ) async throws -> [HiddenWorkerRound] {
        if execution.snapshot.currentStage == .crossReview ||
            execution.snapshot.currentStage == .finalSynthesis,
            execution.snapshot.workersRoundOneSummaries.count == 3 {
            return execution.snapshot.workersRoundOneSummaries.map {
                HiddenWorkerRound(role: $0.role, summary: $0.summary)
            }
        }

        if execution.snapshot.currentStage == .finalSynthesis,
           execution.snapshot.crossReviewSummaries.count == 3 {
            return execution.snapshot.crossReviewSummaries.map {
                HiddenWorkerRound(role: $0.role, summary: $0.summary)
            }
        }

        return try await runWorkerRoundOne(
            apiKey: prepared.apiKey,
            configuration: prepared.configuration,
            conversation: prepared.conversation,
            execution: execution,
            latestUserText: prepared.latestUserText,
            leaderBrief: leaderBrief
        )
    }

    private func resolveCrossReview(
        for prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        firstRound: [HiddenWorkerRound]
    ) async throws -> [HiddenWorkerRevision] {
        if execution.snapshot.currentStage == .finalSynthesis,
           execution.snapshot.crossReviewSummaries.count == 3 {
            return execution.snapshot.crossReviewSummaries.map {
                HiddenWorkerRevision(
                    role: $0.role,
                    summary: $0.summary,
                    adoptedPoints: $0.adoptedPoints
                )
            }
        }

        return try await runCrossReview(
            apiKey: prepared.apiKey,
            configuration: prepared.configuration,
            conversation: prepared.conversation,
            execution: execution,
            latestUserText: prepared.latestUserText,
            firstRound: firstRound
        )
    }

    private func resolveVisibleLeaderSynthesis(
        for prepared: PreparedAgentTurn,
        execution: AgentExecutionState,
        leaderBrief: String,
        revisedWorkers: [HiddenWorkerRevision]
    ) async throws {
        if execution.snapshot.currentStage == .finalSynthesis,
           prepared.configuration.backgroundModeEnabled,
           prepared.draft.responseId != nil {
            try await recoverVisibleLeaderSynthesis(
                apiKey: prepared.apiKey,
                conversation: prepared.conversation,
                draft: prepared.draft,
                execution: execution
            )
            return
        }

        try await runVisibleLeaderSynthesis(
            apiKey: prepared.apiKey,
            configuration: prepared.configuration,
            conversation: prepared.conversation,
            execution: execution,
            latestUserText: prepared.latestUserText,
            leaderBrief: leaderBrief,
            revisedWorkers: revisedWorkers
        )
    }
}
