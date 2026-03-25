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

@MainActor
final class AgentRunCoordinator {
    unowned let state: AgentController

    init(state: AgentController) {
        self.state = state
    }

    func startTurn(_ prepared: PreparedAgentTurn) {
        let snapshot = prepared.conversation.agentConversationState?.activeRun
            ?? AgentProcessProjector.makeInitialRunSnapshot(
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
            if !prepared.attachmentsToUpload.isEmpty {
                try await uploadAttachmentsIfNeeded(prepared)
            }

            var snapshot = execution.snapshot
            AgentProcessProjector.prepareForResume(&snapshot)
            execution.snapshot = snapshot
            persistSnapshot(execution, in: prepared.conversation)

            if execution.snapshot.currentStage == .finalSynthesis,
               prepared.configuration.backgroundModeEnabled,
               prepared.draft.responseId != nil {
                try await recoverVisibleLeaderSynthesis(
                    apiKey: prepared.apiKey,
                    conversation: prepared.conversation,
                    draft: prepared.draft,
                    execution: execution
                )
                try finalizeSuccessfulTurn(
                    prepared: prepared,
                    execution: execution,
                    outcome: execution.snapshot.processSnapshot.outcome.isEmpty
                        ? "Completed"
                        : execution.snapshot.processSnapshot.outcome,
                    stopReason: execution.snapshot.processSnapshot.stopReason ?? .sufficientAnswer
                )
                return
            }

            let baseInput = AgentPromptBuilder.visibleConversationInput(from: prepared.conversation.messages)
            let finalDirective = try await executeDynamicLoop(
                prepared: prepared,
                execution: execution,
                baseInput: baseInput
            )

            applyFinalDirective(finalDirective, to: execution, in: prepared.conversation)
            try await runVisibleLeaderSynthesis(
                apiKey: prepared.apiKey,
                configuration: prepared.configuration,
                conversation: prepared.conversation,
                execution: execution,
                baseInput: baseInput
            )
            try finalizeSuccessfulTurn(
                prepared: prepared,
                execution: execution,
                outcome: execution.snapshot.processSnapshot.outcome.isEmpty
                    ? "Completed"
                    : execution.snapshot.processSnapshot.outcome,
                stopReason: execution.snapshot.processSnapshot.stopReason ?? .sufficientAnswer
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
}
