import ChatDomain
import Foundation
import OpenAITransport

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
        let responseData = try scriptedResponseData(for: instructions)
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
}

private extension ScriptedAgentCouncilTransport {
    func scriptedResponseData(
        for instructions: String
    ) throws(OpenAIServiceError) -> Data {
        if instructions.contains("reviewing delegated worker results") {
            return try leaderReviewResponseData()
        }
        if instructions.contains(
            "dynamic Agent team. Work like a Codex leader coordinating subagents"
        ) {
            return try leaderTriageResponseData()
        }
        if instructions.contains("You are Worker") {
            return try workerTaskResponseData(for: instructions)
        }

        throw .requestFailed("Unexpected scripted Agent request.")
    }

    func leaderTriageResponseData() throws(OpenAIServiceError) -> Data {
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
                \(scriptedLeaderPlanLines.joined(separator: "\n"))
                [/PLAN]
                [TASKS]
                \(scriptedLeaderTriageTaskLines.joined(separator: "\n"))
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

    func leaderReviewResponseData() throws(OpenAIServiceError) -> Data {
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
                \(scriptedLeaderCompletedPlanLines.joined(separator: "\n"))
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

    func workerTaskResponseData(
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

    func requestedRole(
        from instructions: String
    ) throws(OpenAIServiceError) -> AgentRole {
        if let role = [AgentRole.workerA, .workerB, .workerC].first(where: {
            instructions.contains($0.displayName)
        }) {
            return role
        }

        throw .requestFailed("Unable to resolve scripted worker role.")
    }

    func requestPayload(
        from request: URLRequest
    ) throws(OpenAIServiceError) -> [String: Any] {
        do {
            return try scriptedRequestPayload(from: request)
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }
}
