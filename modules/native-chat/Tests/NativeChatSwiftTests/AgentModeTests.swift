import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct AgentModeTests {
    @Test func `conversation mode defaults to chat and agent payloads round trip`() {
        let conversation = Conversation()
        #expect(conversation.mode == .chat)
        #expect(conversation.agentConversationState == nil)

        var state = AgentConversationState()
        state.setResponseID("leader_resp", for: .leader)
        state.currentStage = .crossReview
        conversation.mode = .agent
        conversation.agentConversationState = state

        let trace = AgentTurnTrace(
            leaderBriefSummary: "Validate the migration plan.",
            workerSummaries: [
                AgentWorkerSummary(
                    role: .workerA,
                    summary: "Prefer the additive rollout.",
                    adoptedPoints: ["Keep the migration reversible."]
                )
            ],
            completedStage: .finalSynthesis,
            outcome: "Completed"
        )
        let message = Message(
            role: .assistant,
            content: "Final answer",
            agentTrace: trace
        )

        #expect(conversation.mode == .agent)
        #expect(conversation.agentConversationState?.responseID(for: .leader) == "leader_resp")
        #expect(conversation.agentConversationState?.currentStage == .crossReview)
        #expect(message.agentTrace == trace)
    }

    @Test func `tagged output parser extracts leader brief and worker adoption`() {
        let leaderBrief = AgentTaggedOutputParser.parseLeaderBrief(
            from: """
            [BRIEF]
            Focus on shipping an additive migration path.
            [/BRIEF]
            """
        )
        let revision = AgentTaggedOutputParser.parseWorkerRevision(
            from: """
            [SUMMARY]
            Prefer the staged rollout with parity checks.
            [/SUMMARY]
            [ADOPTED]
            - Keep rollback steps explicit.
            - Call out missing monitoring.
            [/ADOPTED]
            """
        )

        #expect(leaderBrief == "Focus on shipping an additive migration path.")
        #expect(revision.summary == "Prefer the staged rollout with parity checks.")
        #expect(revision.adoptedPoints == [
            "Keep rollback steps explicit.",
            "Call out missing monitoring."
        ])
    }

    @Test func `history presenter labels agent conversations as Agent`() throws {
        let container = try makeInMemoryModelContainer()
        let modelContext = ModelContext(container)
        let appStore = NativeChatCompositionRoot(
            modelContext: modelContext,
            bootstrapPolicy: .testing
        ).makeAppStore()

        let agentConversation = Conversation(title: "Agent Review")
        agentConversation.mode = .agent
        let agentMessage = Message(
            role: .assistant,
            content: "Agent summary",
            conversation: agentConversation
        )
        agentConversation.messages = [agentMessage]
        modelContext.insert(agentConversation)
        modelContext.insert(agentMessage)
        try modelContext.save()

        appStore.historyPresenter.refresh()

        let row = try #require(
            appStore.historyPresenter.conversations.first(where: { $0.id == agentConversation.id })
        )
        #expect(row.modelDisplayName == "Agent")
    }

    @Test func `agent mode reuses persisted response ids across follow up turns`() async throws {
        let transport = ScriptedAgentCouncilTransport(
            turns: [
                AgentTurnScript(
                    leaderResponseID: "leader_brief_1",
                    roundOneResponseIDs: [
                        .workerA: "worker_a_round_1",
                        .workerB: "worker_b_round_1",
                        .workerC: "worker_c_round_1"
                    ],
                    revisionResponseIDs: [
                        .workerA: "worker_a_revision_1",
                        .workerB: "worker_b_revision_1",
                        .workerC: "worker_c_revision_1"
                    ]
                ),
                AgentTurnScript(
                    leaderResponseID: "leader_brief_2",
                    roundOneResponseIDs: [
                        .workerA: "worker_a_round_2",
                        .workerB: "worker_b_round_2",
                        .workerC: "worker_c_round_2"
                    ],
                    revisionResponseIDs: [
                        .workerA: "worker_a_revision_2",
                        .workerB: "worker_b_revision_2",
                        .workerC: "worker_c_revision_2"
                    ]
                )
            ]
        )
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [
            [
                .responseCreated("leader_final_1"),
                .textDelta("Final answer 1"),
                .completed("Final answer 1", nil, nil)
            ],
            [
                .responseCreated("leader_final_2"),
                .textDelta("Final answer 2"),
                .completed("Final answer 2", nil, nil)
            ]
        ])
        let controller = try makeTestAgentController(
            transport: transport,
            streamClient: streamClient
        )

        #expect(controller.sendMessage(text: "How should we ship this?"))
        try await waitUntil {
            !controller.isRunning && controller.messages.last?.content == "Final answer 1"
        }

        #expect(controller.sendMessage(text: "What changes for the follow up?"))
        try await waitUntil {
            !controller.isRunning && controller.messages.last?.content == "Final answer 2"
        }

        let finalState = try #require(controller.currentConversation?.agentConversationState)
        #expect(finalState.responseID(for: .leader) == "leader_final_2")
        #expect(finalState.responseID(for: .workerA) == "worker_a_revision_2")
        #expect(finalState.responseID(for: .workerB) == "worker_b_revision_2")
        #expect(finalState.responseID(for: .workerC) == "worker_c_revision_2")

        let recordedRequests = await transport.requests()
        let requestBodies = recordedRequests.compactMap(previousResponseID(from:))

        #expect(requestBodies.contains("leader_final_1"))
        #expect(requestBodies.contains("worker_a_revision_1"))
        #expect(requestBodies.contains("worker_b_revision_1"))
        #expect(requestBodies.contains("worker_c_revision_1"))
    }
}

private struct AgentTurnScript {
    let leaderResponseID: String
    let roundOneResponseIDs: [AgentRole: String]
    let revisionResponseIDs: [AgentRole: String]
}

private actor ScriptedAgentCouncilTransport: OpenAIDataTransport {
    private let turns: [AgentTurnScript]
    private let responseURL = URL(
        string: "https://api.test.openai.local/v1/responses/test"
    ) ?? URL(fileURLWithPath: "/")

    private var recordedRequests: [URLRequest] = []
    private var leaderTurnIndex = 0
    private var roundOneTurnIndexByRole = Dictionary(
        uniqueKeysWithValues: AgentRole.allCases.map { ($0, 0) }
    )
    private var revisionTurnIndexByRole = Dictionary(
        uniqueKeysWithValues: AgentRole.allCases.map { ($0, 0) }
    )

    init(turns: [AgentTurnScript]) {
        self.turns = turns
    }

    func data(
        for request: URLRequest
    ) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        recordedRequests.append(request)

        let payload = try requestPayload(from: request)
        let instructions = payload["instructions"] as? String ?? ""

        let responseData: Data
        if instructions.contains("produce a compact coordination brief") {
            responseData = try leaderBriefResponseData()
        } else if instructions.contains("Review your prior answer and the other workers' summaries") {
            responseData = try crossReviewResponseData(for: instructions)
        } else if instructions.contains("Use the user-visible conversation plus the leader brief") {
            responseData = try workerRoundResponseData(for: instructions)
        } else {
            throw .requestFailed("Unexpected scripted Agent request.")
        }

        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) ?? HTTPURLResponse()
        return (responseData, response)
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }

    private func leaderBriefResponseData() throws(OpenAIServiceError) -> Data {
        guard turns.indices.contains(leaderTurnIndex) else {
            throw .requestFailed("Missing scripted leader response.")
        }

        let responseID = turns[leaderTurnIndex].leaderResponseID
        leaderTurnIndex += 1
        do {
            return try makeAgentResponseData(
                responseID: responseID,
                text: """
                [BRIEF]
                Focus on the strongest shipping path.
                [/BRIEF]
                """
            )
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }

    private func workerRoundResponseData(
        for instructions: String
    ) throws(OpenAIServiceError) -> Data {
        let role = try requestedRole(from: instructions)
        let turnIndex = roundOneTurnIndexByRole[role] ?? 0
        guard turns.indices.contains(turnIndex) else {
            throw .requestFailed("Missing scripted worker round response.")
        }
        guard let responseID = turns[turnIndex].roundOneResponseIDs[role] else {
            throw .requestFailed("Missing scripted worker round id.")
        }

        roundOneTurnIndexByRole[role] = turnIndex + 1
        do {
            return try makeAgentResponseData(
                responseID: responseID,
                text: """
                [SUMMARY]
                \(role.displayName) round summary.
                [/SUMMARY]
                """
            )
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }

    private func crossReviewResponseData(
        for instructions: String
    ) throws(OpenAIServiceError) -> Data {
        let role = try requestedRole(from: instructions)
        let turnIndex = revisionTurnIndexByRole[role] ?? 0
        guard turns.indices.contains(turnIndex) else {
            throw .requestFailed("Missing scripted cross-review response.")
        }
        guard let responseID = turns[turnIndex].revisionResponseIDs[role] else {
            throw .requestFailed("Missing scripted cross-review id.")
        }

        revisionTurnIndexByRole[role] = turnIndex + 1
        do {
            return try makeAgentResponseData(
                responseID: responseID,
                text: """
                [SUMMARY]
                \(role.displayName) revised summary.
                [/SUMMARY]
                [ADOPTED]
                - Added the strongest peer point.
                [/ADOPTED]
                """
            )
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }

    private func requestedRole(
        from instructions: String
    ) throws(OpenAIServiceError) -> AgentRole {
        if let role = [AgentRole.workerA, .workerB, .workerC].first(where: {
            instructions.contains($0.displayName)
        }) {
            return role
        }

        throw .requestFailed("Unable to resolve scripted worker role.")
    }

    private func requestPayload(
        from request: URLRequest
    ) throws(OpenAIServiceError) -> [String: Any] {
        guard let body = request.httpBody else {
            throw .requestFailed("Missing scripted request payload.")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: body)
        } catch {
            throw .requestFailed(error.localizedDescription)
        }

        guard let payload = object as? [String: Any] else {
            throw .requestFailed("Missing scripted request payload.")
        }

        return payload
    }
}

private func makeAgentResponseData(
    responseID: String,
    text: String
) throws -> Data {
    try JSONCoding.encode(
        ResponsesResponseDTO(
            id: responseID,
            status: "completed",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    role: "assistant",
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: text
                        )
                    ]
                )
            ]
        )
    )
}

private func previousResponseID(from request: URLRequest) -> String? {
    guard
        let body = request.httpBody,
        let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else {
        return nil
    }

    return payload["previous_response_id"] as? String
}
