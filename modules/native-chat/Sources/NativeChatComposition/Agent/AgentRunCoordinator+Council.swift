import ChatDomain
import OpenAITransport

extension AgentRunCoordinator {
    func runLeaderBrief(
        apiKey: String,
        baseInput: [ResponsesInputMessageDTO]
    ) async throws -> String {
        updateStage(.leaderBrief)
        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: baseInput,
            instructions: AgentPromptBuilder.leaderBriefInstructions(),
            previousResponseID: currentAgentState.responseID(for: .leader),
            reasoningEffort: .high,
            serviceTier: .standard
        )
        try updateRoleResponseID(requireResponseID(from: response), for: .leader)
        let output = state.responseParser.extractOutputText(from: response)
        return AgentTaggedOutputParser.parseLeaderBrief(from: output)
    }

    func runWorkerRoundOne(
        apiKey: String,
        latestUserText: String,
        leaderBrief: String
    ) async throws -> [HiddenWorkerRound] {
        setAllWorkerStatuses(.running)

        async let workerA = runWorkerRoundOne(
            apiKey: apiKey,
            role: .workerA,
            latestUserText: latestUserText,
            leaderBrief: leaderBrief
        )
        async let workerB = runWorkerRoundOne(
            apiKey: apiKey,
            role: .workerB,
            latestUserText: latestUserText,
            leaderBrief: leaderBrief
        )
        async let workerC = runWorkerRoundOne(
            apiKey: apiKey,
            role: .workerC,
            latestUserText: latestUserText,
            leaderBrief: leaderBrief
        )

        return try await [workerA, workerB, workerC]
    }

    func runCrossReview(
        apiKey: String,
        latestUserText: String,
        firstRound: [HiddenWorkerRound]
    ) async throws -> [HiddenWorkerRevision] {
        setAllWorkerStatuses(.running)

        async let workerA = runCrossReview(
            apiKey: apiKey,
            role: .workerA,
            latestUserText: latestUserText,
            firstRound: firstRound
        )
        async let workerB = runCrossReview(
            apiKey: apiKey,
            role: .workerB,
            latestUserText: latestUserText,
            firstRound: firstRound
        )
        async let workerC = runCrossReview(
            apiKey: apiKey,
            role: .workerC,
            latestUserText: latestUserText,
            firstRound: firstRound
        )

        return try await [workerA, workerB, workerC]
    }

    func runVisibleLeaderSynthesis(
        apiKey: String,
        latestUserText: String,
        leaderBrief: String,
        revisedWorkers: [HiddenWorkerRevision],
        service: OpenAIService
    ) async throws {
        state.isStreaming = true
        state.isThinking = false

        let stream = service.streamResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.finalSynthesisInput(
                latestUserText: latestUserText,
                leaderBrief: leaderBrief,
                workerSummaries: makeWorkerSummaries(from: revisedWorkers)
            ),
            instructions: AgentPromptBuilder.finalSynthesisInstructions(),
            previousResponseID: currentAgentState.responseID(for: .leader),
            reasoningEffort: .high,
            serviceTier: .standard
        )

        for await event in stream {
            try Task.checkCancellation()
            try applyVisibleStreamEvent(event)
        }
    }

    private func runWorkerRoundOne(
        apiKey: String,
        role: AgentRole,
        latestUserText: String,
        leaderBrief: String
    ) async throws -> HiddenWorkerRound {
        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.workerRoundInput(
                latestUserText: latestUserText,
                leaderBrief: leaderBrief
            ),
            instructions: AgentPromptBuilder.workerRoundInstructions(for: role),
            previousResponseID: currentAgentState.responseID(for: role),
            reasoningEffort: .low,
            serviceTier: .standard
        )
        try updateRoleResponseID(requireResponseID(from: response), for: role)
        setWorkerStatus(.completed, for: role)
        return HiddenWorkerRound(
            role: role,
            summary: AgentTaggedOutputParser.parseWorkerSummary(
                from: state.responseParser.extractOutputText(from: response)
            )
        )
    }

    private func runCrossReview(
        apiKey: String,
        role: AgentRole,
        latestUserText: String,
        firstRound: [HiddenWorkerRound]
    ) async throws -> HiddenWorkerRevision {
        guard let ownSummary = firstRound.first(where: { $0.role == role })?.summary else {
            throw AgentRunFailure.invalidResponse("Missing worker summary for \(role.displayName).")
        }

        let peerSummaries = firstRound
            .filter { $0.role != role }
            .map(\.summary)
        let response = try await state.serviceFactory().createResponse(
            apiKey: apiKey,
            modelIdentifier: ModelType.gpt5_4.rawValue,
            input: AgentPromptBuilder.crossReviewInput(
                latestUserText: latestUserText,
                ownSummary: ownSummary,
                peerSummaries: peerSummaries
            ),
            instructions: AgentPromptBuilder.crossReviewInstructions(for: role),
            previousResponseID: currentAgentState.responseID(for: role),
            reasoningEffort: .low,
            serviceTier: .standard
        )
        try updateRoleResponseID(requireResponseID(from: response), for: role)
        setWorkerStatus(.completed, for: role)

        let parsed = AgentTaggedOutputParser.parseWorkerRevision(
            from: state.responseParser.extractOutputText(from: response)
        )
        return HiddenWorkerRevision(
            role: role,
            summary: parsed.summary,
            adoptedPoints: parsed.adoptedPoints
        )
    }

    func makeWorkerSummaries(from revisions: [HiddenWorkerRevision]) -> [AgentWorkerSummary] {
        revisions.map {
            AgentWorkerSummary(
                role: $0.role,
                summary: $0.summary,
                adoptedPoints: $0.adoptedPoints
            )
        }
    }
}
