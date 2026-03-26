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
            execution.snapshot.runConfiguration = frozenRunConfiguration(
                for: execution,
                conversation: prepared.conversation
            )
            execution.snapshot.hasExplicitRunConfiguration = true

            if !prepared.attachmentsToUpload.isEmpty {
                AgentProcessProjector.updatePhase(
                    .attachmentUpload,
                    leaderStatus: "Uploading attachments",
                    on: &execution.snapshot
                )
                AgentProcessProjector.updateLeaderLivePreview(
                    status: "Uploading attachments",
                    summary: "Preparing the current turn's files before planning begins.",
                    on: &execution.snapshot
                )
                persistCheckpointIfNeeded(
                    execution,
                    in: prepared.conversation,
                    forceSave: execution.snapshot.runConfiguration.backgroundModeEnabled
                )
                try await uploadAttachmentsIfNeeded(prepared, execution: execution)
            }

            var snapshot = execution.snapshot
            AgentProcessProjector.prepareForResume(&snapshot)
            execution.snapshot = snapshot
            if shouldReplayCheckpoint(for: execution.snapshot) {
                AgentProcessProjector.updateRecoveryState(.replayingCheckpoint, on: &execution.snapshot)
            }
            persistSnapshot(execution, in: prepared.conversation)

            if execution.snapshot.currentStage == .finalSynthesis,
               execution.snapshot.runConfiguration.backgroundModeEnabled,
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
                configuration: execution.snapshot.runConfiguration,
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
            visible: state.sessionRegistry.isVisible(prepared.conversation.id)
        )
        syncVisibleStateIfNeeded(execution, in: prepared.conversation)
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            await executeTurn(prepared, execution: execution)
        }
    }

    private func shouldReplayCheckpoint(for snapshot: AgentRunSnapshot) -> Bool {
        guard snapshot.runConfiguration.backgroundModeEnabled else {
            return false
        }

        switch snapshot.phase {
        case .leaderTriage, .leaderLocalPass, .leaderReview:
            return snapshot.leaderTicket?.responseID == nil
        case .workerWave:
            let runningRoles = snapshot.processSnapshot.tasks
                .filter { $0.status == .running || $0.status == .queued }
                .compactMap(\.owner.role)
            guard !runningRoles.isEmpty else { return false }
            return runningRoles.contains { snapshot.ticket(for: $0)?.responseID == nil }
        default:
            return false
        }
    }
}
