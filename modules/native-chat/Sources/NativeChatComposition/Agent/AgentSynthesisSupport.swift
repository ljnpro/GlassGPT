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

        AgentProcessProjector.appendDecision(
            kind: decisionKind,
            title: directive.decision.rawValue.capitalized,
            summary: directive.decisionNote.isEmpty ? focus : directive.decisionNote,
            on: &execution.snapshot
        )

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

        let stream = execution.service.streamResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.finalSynthesisInput(
                baseInput: baseInput,
                snapshot: execution.snapshot.processSnapshot
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

    func uploadAttachmentsIfNeeded(_ prepared: PreparedAgentTurn) async throws {
        var uploadedAttachments = prepared.attachmentsToUpload
        for index in uploadedAttachments.indices {
            if uploadedAttachments[index].fileId != nil {
                uploadedAttachments[index].uploadStatus = .uploaded
                continue
            }

            uploadedAttachments[index].uploadStatus = .uploading
            guard let data = uploadedAttachments[index].localData else {
                uploadedAttachments[index].uploadStatus = .failed
                continue
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
        }

        if let userMessage = prepared.conversation.messages.first(where: { $0.id == prepared.userMessageID }) {
            userMessage.fileAttachments = uploadedAttachments
            prepared.conversation.updatedAt = .now
            guard state.conversationCoordinator.saveContext("uploadAgentAttachments") else {
                throw AgentRunFailure.invalidResponse("Failed to save Agent attachments.")
            }
        }
    }

    func currentCompletedTasks(from snapshot: AgentRunSnapshot) -> [AgentTask] {
        snapshot.processSnapshot.tasks.filter { $0.status == .completed || $0.status == .failed }
    }

    func currentQueuedTasks(from snapshot: AgentRunSnapshot) -> [AgentTask] {
        snapshot.processSnapshot.tasks.filter { $0.status == .queued || $0.status == .running }
    }

    func pendingTasksToRun(from tasks: [AgentTask]) -> [AgentTask] {
        tasks.map { task in
            var task = task
            task.status = .queued
            return task
        }
    }

    func latestDecisionSummary(in snapshot: AgentRunSnapshot) -> String {
        snapshot.processSnapshot.decisions.last?.summary ?? snapshot.processSnapshot.currentFocus
    }

    func updatedTask(for taskID: String, in snapshot: AgentRunSnapshot) -> AgentTask? {
        snapshot.processSnapshot.tasks.first(where: { $0.id == taskID })
    }

    func markPlanStepCompleted(for task: AgentTask, on snapshot: inout AgentRunSnapshot) {
        guard let stepID = task.parentStepID,
              let index = snapshot.processSnapshot.plan.firstIndex(where: { $0.id == stepID })
        else {
            return
        }

        snapshot.processSnapshot.plan[index].status = .completed
        snapshot.updatedAt = .now
        snapshot.processSnapshot.updatedAt = .now
    }

    func mappedStopReason(
        decision: AgentTaggedOutputParser.LeaderDecision,
        stopReasonText: String?
    ) -> AgentStopReason {
        if decision == .clarify {
            return .clarificationRequired
        }

        let text = (stopReasonText ?? "").lowercased()
        if text.contains("budget") || text.contains("limit") {
            return .budgetReached
        }
        if text.contains("tool") || text.contains("search") || text.contains("code") {
            return .toolFailure
        }
        return .sufficientAnswer
    }

    func forceBudgetStopDirective(
        from directive: AgentTaggedOutputParser.LeaderDirective,
        focus: String
    ) -> AgentTaggedOutputParser.LeaderDirective {
        AgentTaggedOutputParser.LeaderDirective(
            focus: focus,
            decision: .finish,
            plan: directive.plan,
            tasks: [],
            decisionNote: "The leader stopped after enough task waves.",
            stopReason: "Budget limit reached; synthesize the best answer from current evidence."
        )
    }
}
