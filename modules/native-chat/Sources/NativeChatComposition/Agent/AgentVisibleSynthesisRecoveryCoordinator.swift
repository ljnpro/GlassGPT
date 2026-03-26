import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func recoverVisibleLeaderSynthesis(
        apiKey: String,
        conversation: Conversation,
        draft: Message,
        execution: AgentExecutionState,
        allowReplayFromCheckpoint: Bool = true
    ) async throws {
        AgentVisibleSynthesisProjector.begin(
            on: &execution.snapshot,
            initialPresentation: AgentVisibleSynthesisPresentation(
                statusText: "Reconnecting",
                summaryText: "Recovering the final answer from the accepted findings.",
                recoveryState: .reconnecting
            )
        )
        persistSnapshot(execution, in: conversation)
        setStreamingFlags(
            isStreaming: true,
            isThinking: execution.snapshot.isThinking,
            execution: execution,
            conversation: conversation,
            persist: false
        )

        guard let responseID = draft.responseId, !responseID.isEmpty else {
            try await restartVisibleLeaderSynthesis(
                apiKey: apiKey,
                conversation: conversation,
                execution: execution,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
            return
        }

        if draft.lastSequenceNumber != nil {
            try await resumeOrRestartVisibleLeaderSynthesis(
                apiKey: apiKey,
                responseID: responseID,
                lastSequenceNumber: draft.lastSequenceNumber,
                conversation: conversation,
                draft: draft,
                execution: execution,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
            return
        }

        let result: OpenAIResponseFetchResult
        do {
            result = try await execution.service.fetchResponse(responseId: responseID, apiKey: apiKey)
        } catch {
            try await resumeOrRestartVisibleLeaderSynthesis(
                apiKey: apiKey,
                responseID: responseID,
                lastSequenceNumber: draft.lastSequenceNumber,
                conversation: conversation,
                draft: draft,
                execution: execution,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
            return
        }

        switch result.status {
        case .completed:
            applyFetchedResponse(result, to: execution, conversation: conversation)
        case .failed, .incomplete:
            try await restartVisibleLeaderSynthesis(
                apiKey: apiKey,
                conversation: conversation,
                execution: execution,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        case .queued, .inProgress, .unknown:
            try await resumeOrRestartVisibleLeaderSynthesis(
                apiKey: apiKey,
                responseID: responseID,
                lastSequenceNumber: draft.lastSequenceNumber,
                conversation: conversation,
                draft: draft,
                execution: execution,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }

    func restartVisibleLeaderSynthesis(
        apiKey: String,
        conversation: Conversation,
        execution: AgentExecutionState,
        allowReplayFromCheckpoint: Bool = true
    ) async throws {
        guard allowReplayFromCheckpoint else {
            throw AgentRunFailure.incomplete("Agent synthesis could not be resumed.")
        }
        let replayBaseResponseID = execution.snapshot.ticket(for: .leader)?.checkpointBaseResponseID
        execution.snapshot.currentStreamingText = ""
        execution.snapshot.currentThinkingText = ""
        execution.snapshot.activeToolCalls = []
        execution.snapshot.liveCitations = []
        execution.snapshot.liveFilePathAnnotations = []
        if let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) {
            draft.content = ""
            draft.thinking = nil
            draft.toolCalls = []
            draft.annotations = []
            draft.filePathAnnotations = []
            draft.lastSequenceNumber = nil
            draft.responseId = nil
        }
        execution.snapshot.visibleSynthesisPresentation = AgentVisibleSynthesisPresentation(
            statusText: "Replaying last checkpoint",
            summaryText: "Restarting the final answer from the accepted Agent findings.",
            recoveryState: .replayingCheckpoint
        )
        persistSnapshot(execution, in: conversation)
        try await runVisibleLeaderSynthesis(
            apiKey: apiKey,
            configuration: execution.snapshot.runConfiguration,
            conversation: conversation,
            execution: execution,
            baseInput: AgentPromptBuilder.visibleConversationInput(from: conversation.messages),
            initialPresentation: AgentVisibleSynthesisPresentation(
                statusText: "Replaying last checkpoint",
                summaryText: "Restarting the final answer from the accepted Agent findings.",
                recoveryState: .replayingCheckpoint
            ),
            previousResponseIDOverride: replayBaseResponseID,
            fallbackToConversationLeaderChain: false,
            allowReplayFromCheckpoint: false
        )
    }
}
