import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

extension AgentRunCoordinator {
    struct FinalSynthesisContext {
        let discussion: AgentPromptBuilder.FinalSynthesisDiscussion
        let workerSummaries: [AgentWorkerSummary]
    }

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
        baseInput: [ResponsesInputMessageDTO]
    ) async throws {
        AgentProcessProjector.beginSynthesis(on: &execution.snapshot)
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
            previousResponseID: currentAgentState(for: conversation).responseID(for: .leader),
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier,
            tools: OpenAIRequestFactory.defaultChatTools(),
            background: configuration.backgroundModeEnabled
        )

        guard let draft = conversation.messages.first(where: { $0.id == execution.draftMessageID }) else {
            throw AgentRunFailure.missingDraft
        }

        for await event in stream {
            try Task.checkCancellation()
            try applyVisibleStreamEvent(
                event,
                execution: execution,
                conversation: conversation,
                draft: draft
            )
        }
    }

    func finalSynthesisContext(from snapshot: AgentProcessSnapshot) -> FinalSynthesisContext {
        let workerSummaries = AgentSummaryFormatter.workerSummaries(from: snapshot)
        let planHighlights = snapshot.plan
            .map {
                "\($0.title) (\($0.status.displayName.lowercased())): \(AgentSummaryFormatter.summarize($0.summary, maxLength: 100))"
            }
            .prefix(4)
            .map(\.self)
        let remainingRisks = [AgentRole.workerA, .workerB, .workerC]
            .compactMap { AgentSummaryFormatter.latestCompletedWorkerTask(role: $0, from: snapshot)?.result?.risks }
            .flatMap(\.self)
        let discussion = AgentPromptBuilder.FinalSynthesisDiscussion(
            leaderFocus: snapshot.leaderAcceptedFocus.isEmpty
                ? (snapshot.currentFocus.isEmpty ? "Respond to the user with the accepted findings." : snapshot.currentFocus)
                : snapshot.leaderAcceptedFocus,
            planHighlights: Array(planHighlights),
            workerSummaries: workerSummaries,
            adoptedEvidence: AgentSummaryFormatter.summarizeBullets(snapshot.evidence, maxItems: 6, maxLength: 120),
            remainingRisks: AgentSummaryFormatter.summarizeBullets(remainingRisks, maxItems: 4, maxLength: 120),
            stopReason: snapshot.stopReason?.displayName ?? "Leader judged the answer sufficient."
        )
        return FinalSynthesisContext(
            discussion: discussion,
            workerSummaries: workerSummaries
        )
    }

    func uploadAttachmentsIfNeeded(
        _ prepared: PreparedAgentTurn,
        execution: AgentExecutionState
    ) async throws {
        var uploadedAttachments = prepared.attachmentsToUpload
        for index in uploadedAttachments.indices {
            if uploadedAttachments[index].fileId != nil {
                uploadedAttachments[index].uploadStatus = .uploaded
                continue
            }

            uploadedAttachments[index].uploadStatus = .uploading
            guard let data = uploadedAttachments[index].localData else {
                uploadedAttachments[index].uploadStatus = .failed
                throw AgentRunFailure.incomplete(
                    "One attachment is unavailable. Retry to continue."
                )
            }

            let request = try state.requestBuilder.uploadRequest(
                data: data,
                filename: uploadedAttachments[index].filename,
                apiKey: prepared.apiKey
            )
            let (responseData, response) = try await state.transport.data(for: request)
            let fileID = try state.responseParser.parseUploadedFileID(
                responseData: responseData,
                response: response
            )
            uploadedAttachments[index].openAIFileId = fileID
            uploadedAttachments[index].uploadStatus = .uploaded

            AgentProcessProjector.updateLeaderLivePreview(
                status: "Uploading attachments",
                summary: "Uploaded \(index + 1) of \(uploadedAttachments.count) attachment(s).",
                on: &execution.snapshot
            )
            persistCheckpointIfNeeded(
                execution,
                in: prepared.conversation,
                forceSave: execution.snapshot.runConfiguration.backgroundModeEnabled
            )
        }

        if let userMessage = prepared.conversation.messages.first(where: { $0.id == prepared.userMessageID }) {
            userMessage.fileAttachments = uploadedAttachments
            prepared.conversation.updatedAt = .now
            guard state.conversationCoordinator.saveContext("uploadAgentAttachments") else {
                throw AgentRunFailure.invalidResponse("Failed to save Agent attachments.")
            }
        }
    }
}
