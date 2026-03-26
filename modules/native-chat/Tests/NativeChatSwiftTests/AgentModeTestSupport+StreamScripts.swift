import ChatDomain
import Foundation
import OpenAITransport

func scriptedRequestPayload(
    from request: URLRequest
) throws -> [String: Any] {
    guard let body = request.httpBody else {
        throw NativeChatTestError.missingStubbedTransportResponse
    }

    let object = try JSONSerialization.jsonObject(with: body)
    guard let payload = object as? [String: Any] else {
        throw NativeChatTestError.missingStubbedTransportResponse
    }

    return payload
}

func scriptedRequestedRole(
    from instructions: String
) throws -> AgentRole {
    if let role = [AgentRole.workerA, .workerB, .workerC].first(where: {
        instructions.contains($0.displayName)
    }) {
        return role
    }

    throw NativeChatTestError.missingStubbedTransportResponse
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

func scriptedWorkerStreamEvents(
    role: AgentRole,
    responseID: String
) -> [StreamEvent] {
    let body = """
    [STATUS]
    Checking \(role.displayName.lowercased())
    [/STATUS]
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

    return [
        .responseCreated(responseID),
        .textDelta(body),
        .completed(body, nil, nil)
    ]
}

func scriptedFinalSynthesisStreamEvents(
    responseID: String,
    answer: String
) -> [StreamEvent] {
    [
        .responseCreated(responseID),
        .textDelta(answer),
        .completed(answer, nil, nil)
    ]
}

func scriptedLeaderTriageStreamEvents(
    responseID: String,
    decision: String = "delegate",
    focus: String = "Leader is shaping the first task wave.",
    decisionNote: String = "Delegate one bounded wave before synthesizing.",
    includeTasks: Bool = true
) -> [StreamEvent] {
    let taskLines = includeTasks ? scriptedLeaderTriageTaskLines : []

    return scriptedLeaderDirectiveStreamEvents(
        responseID: responseID,
        status: "Scoping the request",
        focus: focus,
        decision: decision,
        planLines: scriptedLeaderPlanLines,
        taskLines: taskLines,
        decisionNote: decisionNote,
        stopReason: decision == "finish" ? "Answer completed." : nil
    )
}

func scriptedLeaderReviewStreamEvents(
    responseID: String,
    decision: String = "finish",
    focus: String = "Leader is satisfied with the worker evidence and ready to answer.",
    decisionNote: String = "The current evidence is sufficient for the final answer.",
    includeTasks: Bool = false
) -> [StreamEvent] {
    let taskLines = includeTasks ? scriptedLeaderReviewTaskLines : []

    return scriptedLeaderDirectiveStreamEvents(
        responseID: responseID,
        status: "Reviewing worker results",
        focus: focus,
        decision: decision,
        planLines: scriptedLeaderCompletedPlanLines,
        taskLines: taskLines,
        decisionNote: decisionNote,
        stopReason: decision == "finish" ? "Answer completed." : nil
    )
}

func scriptedLeaderDirectiveStreamEvents(
    responseID: String,
    status: String,
    focus: String,
    decision: String,
    planLines: [String],
    taskLines: [String],
    decisionNote: String,
    stopReason: String?
) -> [StreamEvent] {
    let stopReasonBlock = stopReason.map {
        """
        [STOP_REASON]
        \($0)
        [/STOP_REASON]
        """
    } ?? ""

    let body = """
    [STATUS]
    \(status)
    [/STATUS]
    [FOCUS]
    \(focus)
    [/FOCUS]
    [DECISION]
    \(decision)
    [/DECISION]
    [PLAN]
    \(planLines.joined(separator: "\n"))
    [/PLAN]
    [TASKS]
    \(taskLines.joined(separator: "\n"))
    [/TASKS]
    [DECISION_NOTE]
    \(decisionNote)
    [/DECISION_NOTE]
    \(stopReasonBlock)
    """

    return [
        .responseCreated(responseID),
        .thinkingStarted,
        .textDelta(body),
        .thinkingFinished,
        .completed(body, nil, nil)
    ]
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

let scriptedLeaderPlanLines = [
    "step_root || root || leader || running || Understand request || Frame the answer and decide what to delegate.",
    "step_a || step_root || workerA || planned || Draft strongest answer || Produce the recommended solution.",
    "step_b || step_root || workerB || planned || Stress risks || Surface edge cases and failure modes.",
    "step_c || step_root || workerC || planned || Check completeness || Find missing context and structure gaps."
]

let scriptedLeaderCompletedPlanLines = [
    "step_root || root || leader || completed || Understand request || The team converged on a stable answer.",
    "step_a || step_root || workerA || completed || Draft strongest answer || Recommended path validated.",
    "step_b || step_root || workerB || completed || Stress risks || Edge cases captured.",
    "step_c || step_root || workerC || completed || Check completeness || Structure gaps closed."
]

let scriptedLeaderTriageTaskLines = [
    [
        "workerA",
        "step_a",
        "enabled",
        "Draft strongest answer",
        "Produce the recommended answer path",
        "Return the strongest concise recommendation"
    ].joined(separator: " || "),
    [
        "workerB",
        "step_b",
        "enabled",
        "Stress risks",
        "Surface edge cases and failure modes",
        "Return a concise risk summary"
    ].joined(separator: " || "),
    [
        "workerC",
        "step_c",
        "reasoningOnly",
        "Check completeness",
        "Find missing context and structure gaps",
        "Return concise completeness notes"
    ].joined(separator: " || ")
]

let scriptedLeaderReviewTaskLines = [
    [
        "workerA",
        "step_a",
        "enabled",
        "Validate answer",
        "Pressure-test the current answer",
        "Return concise validation notes"
    ].joined(separator: " || ")
]
