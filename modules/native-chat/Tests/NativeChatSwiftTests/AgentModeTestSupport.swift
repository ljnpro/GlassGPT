import ChatDomain
import Foundation
import OpenAITransport

struct AgentTurnScript {
    let triageResponseID: String
    let reviewResponseID: String
    let taskResponseIDs: [AgentRole: String]

    static func singleTurn() -> AgentTurnScript {
        AgentTurnScript(
            triageResponseID: "leader_triage",
            reviewResponseID: "leader_review",
            taskResponseIDs: [
                .workerA: "worker_a_task",
                .workerB: "worker_b_task",
                .workerC: "worker_c_task"
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
    private var triageTurnIndex = 0
    private var reviewTurnIndex = 0
    private var taskTurnIndexByRole = Dictionary(
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
        if instructions.contains("reviewing delegated worker results") {
            responseData = try leaderReviewResponseData()
        } else if instructions.contains("dynamic Agent team. Work like a Codex leader coordinating subagents") {
            responseData = try leaderTriageResponseData()
        } else if instructions.contains("You are Worker") {
            responseData = try workerTaskResponseData(for: instructions)
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

    private func leaderTriageResponseData() throws(OpenAIServiceError) -> Data {
        guard turns.indices.contains(triageTurnIndex) else {
            throw .requestFailed("Missing scripted leader response.")
        }

        let responseID = turns[triageTurnIndex].triageResponseID
        triageTurnIndex += 1
        do {
            return try makeAgentResponseData(
                responseID: responseID,
                text: """
                [FOCUS]
                Leader is shaping the first task wave.
                [/FOCUS]
                [DECISION]
                delegate
                [/DECISION]
                [PLAN]
                step_root || root || leader || running || Understand request || Frame the answer and decide what to delegate.
                step_a || step_root || workerA || planned || Draft strongest answer || Produce the recommended solution.
                step_b || step_root || workerB || planned || Stress risks || Surface edge cases and failure modes.
                step_c || step_root || workerC || planned || Check completeness || Find missing context and structure gaps.
                [/PLAN]
                [TASKS]
                workerA || step_a || enabled || Draft strongest answer || Produce the recommended answer path || \
                Return the strongest concise recommendation
                workerB || step_b || enabled || Stress risks || Surface edge cases and failure modes || \
                Return a concise risk summary
                workerC || step_c || reasoningOnly || Check completeness || \
                Find missing context and structure gaps || Return concise completeness notes
                [/TASKS]
                [DECISION_NOTE]
                Delegate one bounded wave before synthesizing.
                [/DECISION_NOTE]
                """
            )
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }

    private func leaderReviewResponseData() throws(OpenAIServiceError) -> Data {
        guard turns.indices.contains(reviewTurnIndex) else {
            throw .requestFailed("Missing scripted leader review response.")
        }

        let responseID = turns[reviewTurnIndex].reviewResponseID
        reviewTurnIndex += 1
        do {
            return try makeAgentResponseData(
                responseID: responseID,
                text: """
                [FOCUS]
                Leader is satisfied with the worker evidence and ready to answer.
                [/FOCUS]
                [DECISION]
                finish
                [/DECISION]
                [PLAN]
                step_root || root || leader || completed || Understand request || The team converged on a stable answer.
                step_a || step_root || workerA || completed || Draft strongest answer || Recommended path validated.
                step_b || step_root || workerB || completed || Stress risks || Edge cases captured.
                step_c || step_root || workerC || completed || Check completeness || Structure gaps closed.
                [/PLAN]
                [TASKS]
                [/TASKS]
                [DECISION_NOTE]
                The current evidence is sufficient for the final answer.
                [/DECISION_NOTE]
                [STOP_REASON]
                Answer completed.
                [/STOP_REASON]
                """
            )
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }

    private func workerTaskResponseData(
        for instructions: String
    ) throws(OpenAIServiceError) -> Data {
        let role = try requestedRole(from: instructions)
        let turnIndex = taskTurnIndexByRole[role] ?? 0
        guard turns.indices.contains(turnIndex) else {
            throw .requestFailed("Missing scripted worker task response.")
        }
        guard let responseID = turns[turnIndex].taskResponseIDs[role] else {
            throw .requestFailed("Missing scripted worker task id.")
        }

        taskTurnIndexByRole[role] = turnIndex + 1
        do {
            return try makeAgentResponseData(
                responseID: responseID,
                text: """
                [SUMMARY]
                \(role.displayName) task summary.
                [/SUMMARY]
                [EVIDENCE]
                - \(role.displayName) evidence point.
                [/EVIDENCE]
                [CONFIDENCE]
                high
                [/CONFIDENCE]
                [RISKS]
                - \(role.displayName) residual risk.
                [/RISKS]
                [FOLLOW_UP]
                [/FOLLOW_UP]
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
