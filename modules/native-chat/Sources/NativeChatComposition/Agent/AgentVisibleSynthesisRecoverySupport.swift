import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func pollVisibleLeaderSynthesis(
        apiKey: String,
        responseID: String,
        execution: AgentExecutionState,
        conversation: Conversation
    ) async throws {
        let maxAttempts = 30

        for attempt in 0 ..< maxAttempts {
            try Task.checkCancellation()
            let result = try await execution.service.fetchResponse(responseId: responseID, apiKey: apiKey)

            switch result.status {
            case .completed:
                applyFetchedResponse(result, to: execution, conversation: conversation)
                return
            case .failed:
                throw AgentRunFailure.invalidResponse(
                    result.errorMessage ?? "Agent synthesis failed."
                )
            case .incomplete:
                applyFetchedResponse(result, to: execution, conversation: conversation)
                throw AgentRunFailure.incomplete(
                    result.errorMessage ?? "Agent synthesis was incomplete."
                )
            case .queued, .inProgress, .unknown:
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }

        throw AgentRunFailure.incomplete("Agent synthesis is still in progress. Retry to continue.")
    }

    func applyFetchedResponse(
        _ result: OpenAIResponseFetchResult,
        to execution: AgentExecutionState,
        conversation: Conversation
    ) {
        if let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) {
            draft.content = result.text
            draft.thinking = result.thinking
            draft.toolCalls = result.toolCalls
            draft.annotations = result.annotations
            draft.filePathAnnotations = result.filePathAnnotations
        }

        execution.snapshot.currentStreamingText = result.text
        execution.snapshot.currentThinkingText = result.thinking ?? ""
        execution.snapshot.liveCitations = result.annotations
        execution.snapshot.activeToolCalls = result.toolCalls
        execution.snapshot.liveFilePathAnnotations = result.filePathAnnotations
        execution.snapshot.isStreaming = false
        execution.snapshot.isThinking = false
        execution.snapshot.visibleSynthesisPresentation = AgentVisibleSynthesisPresentation(
            statusText: "Writing final answer",
            summaryText: "Writing final answer from accepted findings.",
            recoveryState: .idle
        )
        execution.snapshot.updatedAt = .now
        execution.markProgress()
        syncVisibleStateIfNeeded(execution, in: conversation)
    }

    func resumeOrRestartVisibleLeaderSynthesis(
        apiKey: String,
        responseID: String,
        lastSequenceNumber: Int?,
        conversation: Conversation,
        draft: Message,
        execution: AgentExecutionState,
        allowReplayFromCheckpoint: Bool
    ) async throws {
        if let lastSequenceNumber {
            let recoveryStream = AgentRecoveryStreamMonitoring.monitoredStream(
                execution.service.streamRecovery(
                    responseId: responseID,
                    startingAfter: lastSequenceNumber,
                    apiKey: apiKey
                ),
                onTimeout: {
                    execution.service.cancelStream()
                }
            )
            var didReceiveTerminalEvent = false
            do {
                for await event in recoveryStream {
                    try Task.checkCancellation()
                    switch event {
                    case .completed, .incomplete:
                        didReceiveTerminalEvent = true
                    default:
                        break
                    }
                    try applyVisibleStreamEvent(
                        event,
                        execution: execution,
                        conversation: conversation,
                        draft: draft
                    )
                }
                if didReceiveTerminalEvent {
                    return
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                Loggers.persistence.debug(
                    "[AgentRunRecovery.resumeOrRestartVisibleLeaderSynthesis] "
                        + "Stream recovery failed; falling back to fetch/poll: "
                        + "\(error.localizedDescription)"
                )
            }
        }

        do {
            try await pollVisibleLeaderSynthesis(
                apiKey: apiKey,
                responseID: responseID,
                execution: execution,
                conversation: conversation
            )
            return
        } catch {
            Loggers.persistence.debug(
                "[AgentRunRecovery.resumeOrRestartVisibleLeaderSynthesis] "
                    + "Falling back to replay after polling failed: "
                    + "\(error.localizedDescription)"
            )
        }

        try await restartVisibleLeaderSynthesis(
            apiKey: apiKey,
            conversation: conversation,
            execution: execution,
            allowReplayFromCheckpoint: allowReplayFromCheckpoint
        )
    }
}
