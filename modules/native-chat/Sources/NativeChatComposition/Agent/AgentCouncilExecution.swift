import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func runLeaderBrief(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> String {
        updateStage(.leaderBrief, execution: execution, in: conversation)
        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: baseInput,
            instructions: AgentPromptBuilder.leaderBriefInstructions(),
            previousResponseID: currentAgentState(for: conversation).responseID(for: .leader),
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier
        )
        try updateRoleResponseID(requireResponseID(from: response), for: .leader, in: conversation)
        let output = state.responseParser.extractOutputText(from: response)
        let brief = AgentTaggedOutputParser.parseLeaderBrief(from: output)
        updateLeaderBriefSummary(brief, execution: execution, conversation: conversation)
        return brief
    }

    func runWorkerRoundOne(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        latestUserText: String,
        leaderBrief: String
    ) async throws -> [HiddenWorkerRound] {
        updateStage(.workersRoundOne, execution: execution, in: conversation)

        let tasks = [
            Task { @MainActor in
                try await runWorkerRoundOne(
                    apiKey: apiKey,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    role: .workerA,
                    latestUserText: latestUserText,
                    leaderBrief: leaderBrief
                )
            },
            Task { @MainActor in
                try await runWorkerRoundOne(
                    apiKey: apiKey,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    role: .workerB,
                    latestUserText: latestUserText,
                    leaderBrief: leaderBrief
                )
            },
            Task { @MainActor in
                try await runWorkerRoundOne(
                    apiKey: apiKey,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    role: .workerC,
                    latestUserText: latestUserText,
                    leaderBrief: leaderBrief
                )
            }
        ]
        defer { tasks.forEach { $0.cancel() } }

        var rounds: [HiddenWorkerRound] = []
        for task in tasks {
            try await rounds.append(task.value)
        }
        storeWorkerRoundOneSummaries(rounds, execution: execution, conversation: conversation)
        return rounds
    }

    func runCrossReview(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        latestUserText: String,
        firstRound: [HiddenWorkerRound]
    ) async throws -> [HiddenWorkerRevision] {
        updateStage(.crossReview, execution: execution, in: conversation)

        let tasks = [
            Task { @MainActor in
                try await runCrossReview(
                    apiKey: apiKey,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    role: .workerA,
                    latestUserText: latestUserText,
                    firstRound: firstRound
                )
            },
            Task { @MainActor in
                try await runCrossReview(
                    apiKey: apiKey,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    role: .workerB,
                    latestUserText: latestUserText,
                    firstRound: firstRound
                )
            },
            Task { @MainActor in
                try await runCrossReview(
                    apiKey: apiKey,
                    configuration: configuration,
                    conversation: conversation,
                    execution: execution,
                    role: .workerC,
                    latestUserText: latestUserText,
                    firstRound: firstRound
                )
            }
        ]
        defer { tasks.forEach { $0.cancel() } }

        var revisions: [HiddenWorkerRevision] = []
        for task in tasks {
            try await revisions.append(task.value)
        }
        storeCrossReviewSummaries(revisions, execution: execution, conversation: conversation)
        return revisions
    }

    func runVisibleLeaderSynthesis(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        latestUserText: String,
        leaderBrief: String,
        revisedWorkers: [HiddenWorkerRevision]
    ) async throws {
        updateStage(.finalSynthesis, execution: execution, in: conversation)
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
                latestUserText: latestUserText,
                leaderBrief: leaderBrief,
                workerSummaries: makeWorkerSummaries(from: revisedWorkers)
            ),
            instructions: AgentPromptBuilder.finalSynthesisInstructions(),
            previousResponseID: currentAgentState(for: conversation).responseID(for: .leader),
            reasoningEffort: configuration.leaderReasoningEffort,
            serviceTier: configuration.serviceTier,
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

    func makeWorkerSummaries(from revisions: [HiddenWorkerRevision]) -> [AgentWorkerSummary] {
        revisions
            .sorted { lhs, rhs in
                AgentRole.allCases.firstIndex(of: lhs.role) ?? 0 <
                    (AgentRole.allCases.firstIndex(of: rhs.role) ?? 0)
            }
            .map {
                AgentWorkerSummary(
                    role: $0.role,
                    summary: $0.summary,
                    adoptedPoints: $0.adoptedPoints
                )
            }
    }
}
