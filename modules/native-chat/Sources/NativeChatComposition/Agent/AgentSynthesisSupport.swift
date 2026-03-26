import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    func applyLeaderDirective(
        _ directive: AgentTaggedOutputParser.LeaderDirective,
        decisionKind: AgentDecisionKind,
        to execution: AgentExecutionState,
        in conversation: Conversation,
        appendTasks: Bool
    ) {
        let focus = directive.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty {
            AgentProcessProjector.updateFocus(
                focus,
                activity: directive.decision == .delegate ? .delegation : .reviewing,
                on: &execution.snapshot
            )
            execution.snapshot.leaderBriefSummary = focus
        }

        if !directive.plan.isEmpty {
            AgentProcessProjector.replacePlan(directive.plan, on: &execution.snapshot)
        }

        if directive.decision == .delegate {
            AgentProcessProjector.appendDecision(
                kind: decisionKind,
                title: directive.decision.rawValue.capitalized,
                summary: directive.decisionNote.isEmpty ? focus : directive.decisionNote,
                on: &execution.snapshot
            )
        }

        if appendTasks, !directive.tasks.isEmpty {
            let tasks = directive.tasks.map { task -> AgentTask in
                var task = task
                task.status = .queued
                task.contextSummary = focus
                return task
            }
            AgentProcessProjector.queueTasks(tasks, on: &execution.snapshot)
        }

        persistSnapshot(execution, in: conversation)
    }

    func applyFinalDirective(
        _ directive: AgentTaggedOutputParser.LeaderDirective,
        to execution: AgentExecutionState,
        in conversation: Conversation
    ) {
        let stopReason = mappedStopReason(
            decision: directive.decision,
            stopReasonText: directive.stopReason
        )
        let outcome = directive.stopReason ?? stopReason.displayName
        let decisionKind: AgentDecisionKind = directive.decision == .clarify ? .clarify : .finish
        let title = directive.decision == .clarify ? "Clarify" : "Finish"

        AgentProcessProjector.appendDecision(
            kind: decisionKind,
            title: title,
            summary: directive.decisionNote.isEmpty ? outcome : directive.decisionNote,
            on: &execution.snapshot
        )
        AgentProcessProjector.finalize(
            outcome: outcome,
            stopReason: stopReason,
            activity: directive.decision == .clarify ? .waitingForUser : .completed,
            on: &execution.snapshot
        )
        execution.snapshot.leaderBriefSummary = directive.focus
        persistSnapshot(execution, in: conversation)
    }

    func runVisibleLeaderSynthesis(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO],
        initialPresentation: AgentVisibleSynthesisPresentation? = nil,
        previousResponseIDOverride: String? = nil,
        fallbackToConversationLeaderChain: Bool = true,
        allowReplayFromCheckpoint: Bool = true
    ) async throws {
        let presentation = initialPresentation ?? AgentVisibleSynthesisPresentation(
            statusText: "Writing final answer",
            summaryText: "Writing final answer from accepted findings.",
            recoveryState: .idle
        )
        let checkpointBaseResponseID = previousResponseIDOverride
            ?? execution.snapshot.ticket(for: .leader)?.checkpointBaseResponseID
            ?? (fallbackToConversationLeaderChain
                ? currentAgentState(for: conversation).responseID(for: .leader)
                : nil)
        AgentVisibleSynthesisProjector.begin(
            on: &execution.snapshot,
            initialPresentation: presentation
        )
        AgentVisibleSynthesisEventApplier.persistVisibleLeaderTicket(
            responseID: nil,
            checkpointBaseResponseID: checkpointBaseResponseID,
            sequenceNumber: nil,
            execution: execution,
            conversation: conversation,
            coordinator: self,
            forceSave: true
        )
        persistSnapshot(execution, in: conversation)
        setStreamingFlags(
            isStreaming: true,
            isThinking: false,
            execution: execution,
            conversation: conversation,
            persist: false
        )
        let synthesisContext = finalSynthesisContext(from: execution.snapshot.processSnapshot)

        let stream = execution.service.streamResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.finalSynthesisInput(
                baseInput: baseInput,
                discussion: synthesisContext.discussion
            ),
            instructions: AgentPromptBuilder.finalSynthesisInstructions(),
            previousResponseID: checkpointBaseResponseID,
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: OpenAIRequestFactory.defaultChatTools(),
            background: configuration.backgroundModeEnabled
        )

        guard let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) else {
            throw AgentRunFailure.missingDraft
        }

        do {
            for await event in stream {
                try Task.checkCancellation()
                try applyVisibleStreamEvent(
                    event,
                    execution: execution,
                    conversation: conversation,
                    draft: draft
                )
            }
        } catch let failure as AgentRunFailure
            where allowReplayFromCheckpoint {
            _ = failure
            try await recoverVisibleLeaderSynthesis(
                apiKey: apiKey,
                conversation: conversation,
                draft: draft,
                execution: execution,
                allowReplayFromCheckpoint: allowReplayFromCheckpoint
            )
        }
    }
}
