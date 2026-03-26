import ChatDomain
import Foundation
import OpenAITransport

struct AgentTurnScript {
    let triageResponseID: String
    let localPassResponseID: String?
    let reviewResponseID: String
    let taskResponseIDs: [AgentRole: String]
    let finalResponseID: String
    let finalAnswer: String

    init(
        triageResponseID: String,
        localPassResponseID: String? = nil,
        reviewResponseID: String,
        taskResponseIDs: [AgentRole: String],
        finalResponseID: String = "leader_final",
        finalAnswer: String = "Final answer"
    ) {
        self.triageResponseID = triageResponseID
        self.localPassResponseID = localPassResponseID
        self.reviewResponseID = reviewResponseID
        self.taskResponseIDs = taskResponseIDs
        self.finalResponseID = finalResponseID
        self.finalAnswer = finalAnswer
    }

    static func singleTurn() -> AgentTurnScript {
        AgentTurnScript(
            triageResponseID: "leader_triage",
            reviewResponseID: "leader_review",
            taskResponseIDs: [
                .workerA: "worker_a_task",
                .workerB: "worker_b_task",
                .workerC: "worker_c_task"
            ],
            finalResponseID: "leader_final",
            finalAnswer: "Final answer"
        )
    }
}

struct LegacyAgentConversationStatePayload: Codable {
    let leaderResponseID: String?
    let currentStage: AgentStage?
}

@MainActor
final class ScriptedAgentCouncilStreamClient: OpenAIStreamClient {
    private(set) var recordedRequests: [URLRequest] = []
    private(set) var cancelCallCount = 0

    private let turns: [AgentTurnScript]
    private let controlledResponseIDs: Set<String>
    private var triageTurnIndex = 0
    private var localPassTurnIndex = 0
    private var reviewTurnIndex = 0
    private var finalTurnIndex = 0
    private var taskTurnIndexByRole = Dictionary(
        uniqueKeysWithValues: AgentRole.allCases.map { ($0, 0) }
    )
    private var continuations: [String: AsyncStream<StreamEvent>.Continuation] = [:]

    init(
        turns: [AgentTurnScript],
        controlledResponseIDs: Set<String> = []
    ) {
        self.turns = turns
        self.controlledResponseIDs = controlledResponseIDs
    }

    var activeStreamCount: Int {
        continuations.count
    }

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        recordedRequests.append(request)

        let payload = (try? scriptedRequestPayload(from: request)) ?? [:]
        let instructions = payload["instructions"] as? String ?? ""

        do {
            if instructions.contains("writing the final user-facing answer") {
                return try makeFinalSynthesisStream()
            }
            if instructions.contains("reviewing delegated worker results") {
                return try makeLeaderReviewStream()
            }
            if instructions.contains("doing a short local pass before delegation") {
                return try makeLeaderLocalPassStream()
            }
            if instructions.contains(
                "dynamic Agent team. Work like a Codex leader coordinating subagents"
            ) {
                return try makeLeaderTriageStream()
            }
            if instructions.contains("You are Worker") {
                let role = try scriptedRequestedRole(from: instructions)
                return try makeWorkerTaskStream(for: role)
            }
        } catch {
            return failingStream(message: error.localizedDescription)
        }

        return failingStream(message: "Unexpected scripted Agent stream request.")
    }

    func cancel() {
        cancelCallCount += 1
        finishAll()
    }

    func yield(
        _ event: StreamEvent,
        onResponseID responseID: String? = nil
    ) {
        guard let responseID = responseID ?? continuations.keys.sorted().first,
              let continuation = continuations[responseID]
        else {
            return
        }

        continuation.yield(event)
    }

    func finishStream(responseID: String? = nil) {
        guard let responseID = responseID ?? continuations.keys.sorted().first,
              let continuation = continuations.removeValue(forKey: responseID)
        else {
            return
        }

        continuation.finish()
    }

    func finishAll() {
        let activeContinuations = continuations.values
        continuations.removeAll()
        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func makeLeaderTriageStream() throws -> AsyncStream<StreamEvent> {
        guard turns.indices.contains(triageTurnIndex) else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }

        let turn = turns[triageTurnIndex]
        triageTurnIndex += 1
        return stream(
            scriptedLeaderTriageStreamEvents(responseID: turn.triageResponseID)
        )
    }

    private func makeLeaderLocalPassStream() throws -> AsyncStream<StreamEvent> {
        guard turns.indices.contains(localPassTurnIndex) else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }

        let turn = turns[localPassTurnIndex]
        localPassTurnIndex += 1
        let responseID = turn.localPassResponseID ?? "\(turn.triageResponseID)_local"
        let taskLine = [
            "workerA",
            "step_root",
            "enabled",
            "Validate approach",
            "Test the leading answer path",
            "Return concise validation notes"
        ].joined(separator: " || ")
        return stream(
            scriptedLeaderDirectiveStreamEvents(
                responseID: responseID,
                status: "Refining task briefs",
                focus: "Leader is doing a short local pass before delegating.",
                decision: "delegate",
                planLines: [
                    "step_root || root || leader || running || Refine plan || Tighten the next worker wave."
                ],
                taskLines: [
                    taskLine
                ],
                decisionNote: "Run one refined worker task before synthesis.",
                stopReason: nil
            )
        )
    }

    private func makeLeaderReviewStream() throws -> AsyncStream<StreamEvent> {
        guard turns.indices.contains(reviewTurnIndex) else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }

        let turn = turns[reviewTurnIndex]
        reviewTurnIndex += 1
        return stream(
            scriptedLeaderReviewStreamEvents(responseID: turn.reviewResponseID)
        )
    }

    private func makeWorkerTaskStream(
        for role: AgentRole
    ) throws -> AsyncStream<StreamEvent> {
        let turnIndex = taskTurnIndexByRole[role] ?? 0
        guard turns.indices.contains(turnIndex) else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }
        guard let responseID = turns[turnIndex].taskResponseIDs[role] else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }

        taskTurnIndexByRole[role] = turnIndex + 1
        return stream(scriptedWorkerStreamEvents(role: role, responseID: responseID))
    }

    private func makeFinalSynthesisStream() throws -> AsyncStream<StreamEvent> {
        guard turns.indices.contains(finalTurnIndex) else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }

        let turn = turns[finalTurnIndex]
        finalTurnIndex += 1

        if controlledResponseIDs.contains(turn.finalResponseID) {
            return AsyncStream { continuation in
                continuations[turn.finalResponseID] = continuation
            }
        }

        return stream(
            scriptedFinalSynthesisStreamEvents(
                responseID: turn.finalResponseID,
                answer: turn.finalAnswer
            )
        )
    }

    private func stream(_ events: [StreamEvent]) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    private func failingStream(message: String) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            continuation.yield(.error(OpenAIServiceError.requestFailed(message)))
            continuation.finish()
        }
    }
}
