import ChatDomain
import Foundation
import OpenAITransport

struct AgentTurnScript {
    let leaderResponseID: String
    let roundOneResponseIDs: [AgentRole: String]
    let revisionResponseIDs: [AgentRole: String]

    static func singleTurn() -> AgentTurnScript {
        AgentTurnScript(
            leaderResponseID: "leader_brief",
            roundOneResponseIDs: [
                .workerA: "worker_a_round",
                .workerB: "worker_b_round",
                .workerC: "worker_c_round"
            ],
            revisionResponseIDs: [
                .workerA: "worker_a_revision",
                .workerB: "worker_b_revision",
                .workerC: "worker_c_revision"
            ]
        )
    }
}

struct LegacyAgentConversationStatePayload: Codable {
    let leaderResponseID: String?
    let currentStage: AgentStage?
}

actor ScriptedAgentCouncilTransport: OpenAIDataTransport {
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

func makeAgentResponseData(
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

func previousResponseID(from request: URLRequest) -> String? {
    guard
        let body = request.httpBody,
        let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else {
        return nil
    }

    return payload["previous_response_id"] as? String
}
