import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func runWorkerRoundOne(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        role: AgentRole,
        latestUserText: String,
        leaderBrief: String
    ) async throws -> HiddenWorkerRound {
        setWorkerStatus(
            .running,
            for: role,
            stage: .workersRoundOne,
            execution: execution,
            conversation: conversation
        )
        do {
            let response = try await state.serviceFactory().createResponse(
                apiKey: apiKey,
                modelIdentifier: ModelType.gpt5_4.rawValue,
                input: AgentPromptBuilder.workerRoundInput(
                    latestUserText: latestUserText,
                    leaderBrief: leaderBrief
                ),
                instructions: AgentPromptBuilder.workerRoundInstructions(for: role),
                previousResponseID: currentAgentState(for: conversation).responseID(for: role),
                reasoningEffort: configuration.workerReasoningEffort,
                serviceTier: configuration.serviceTier
            )
            try updateRoleResponseID(requireResponseID(from: response), for: role, in: conversation)
            setWorkerStatus(
                .completed,
                for: role,
                stage: .workersRoundOne,
                execution: execution,
                conversation: conversation
            )
            return HiddenWorkerRound(
                role: role,
                summary: AgentTaggedOutputParser.parseWorkerSummary(
                    from: state.responseParser.extractOutputText(from: response)
                )
            )
        } catch {
            setWorkerStatus(
                .failed,
                for: role,
                stage: .workersRoundOne,
                execution: execution,
                conversation: conversation
            )
            throw error
        }
    }

    func runCrossReview(
        apiKey: String,
        configuration: AgentConversationConfiguration,
        conversation: Conversation,
        execution: AgentExecutionState,
        role: AgentRole,
        latestUserText: String,
        firstRound: [HiddenWorkerRound]
    ) async throws -> HiddenWorkerRevision {
        guard let ownSummary = firstRound.first(where: { $0.role == role })?.summary else {
            throw AgentRunFailure.invalidResponse("Missing worker summary for \(role.displayName).")
        }

        setWorkerStatus(
            .running,
            for: role,
            stage: .crossReview,
            execution: execution,
            conversation: conversation
        )
        do {
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
                previousResponseID: currentAgentState(for: conversation).responseID(for: role),
                reasoningEffort: configuration.workerReasoningEffort,
                serviceTier: configuration.serviceTier
            )
            try updateRoleResponseID(requireResponseID(from: response), for: role, in: conversation)
            setWorkerStatus(
                .completed,
                for: role,
                stage: .crossReview,
                execution: execution,
                conversation: conversation
            )

            let parsed = AgentTaggedOutputParser.parseWorkerRevision(
                from: state.responseParser.extractOutputText(from: response)
            )
            return HiddenWorkerRevision(
                role: role,
                summary: parsed.summary,
                adoptedPoints: parsed.adoptedPoints
            )
        } catch {
            setWorkerStatus(
                .failed,
                for: role,
                stage: .crossReview,
                execution: execution,
                conversation: conversation
            )
            throw error
        }
    }
}
