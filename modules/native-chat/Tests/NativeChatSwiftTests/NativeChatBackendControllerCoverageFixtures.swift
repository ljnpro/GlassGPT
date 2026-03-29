import BackendClient
import BackendContracts
import ChatDomain
import Foundation
import Testing

func makeAgentRun(
    status: RunStatusDTO,
    stage: AgentStageDTO? = nil,
    summary: String? = nil
) -> RunSummaryDTO {
    let now = Date.now
    return RunSummaryDTO(
        id: "run_1",
        conversationID: "conv_1",
        kind: .agent,
        status: status,
        stage: stage,
        createdAt: now,
        updatedAt: now,
        lastEventCursor: nil,
        visibleSummary: summary,
        processSnapshotJSON: nil
    )
}

func makeChatRunSummary(
    id: String,
    status: RunStatusDTO,
    summary: String? = nil
) -> RunSummaryDTO {
    let now = Date.now
    return RunSummaryDTO(
        id: id,
        conversationID: "conv_1",
        kind: .chat,
        status: status,
        stage: nil,
        createdAt: now,
        updatedAt: now,
        lastEventCursor: nil,
        visibleSummary: summary,
        processSnapshotJSON: nil
    )
}

func makeChatConversationDetailSnapshot(
    conversationID: String,
    runID: String,
    assistantContent: String
) throws -> ConversationDetailDTO {
    ConversationDetailDTO(
        conversation: ConversationDTO(
            id: conversationID,
            title: "Chat Thread",
            mode: .chat,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: runID,
            lastSyncCursor: "cur_final"
        ),
        messages: [
            MessageDTO(
                id: "msg_user",
                conversationID: conversationID,
                role: .user,
                content: "Question",
                thinking: nil,
                createdAt: .now,
                completedAt: .now,
                serverCursor: "cur_user",
                runID: nil,
                annotations: nil,
                toolCalls: nil,
                filePathAnnotations: nil,
                agentTraceJSON: nil
            ),
            MessageDTO(
                id: "msg_assistant",
                conversationID: conversationID,
                role: .assistant,
                content: assistantContent,
                thinking: nil,
                createdAt: .now,
                completedAt: .now,
                serverCursor: "cur_assistant",
                runID: runID,
                annotations: [URLCitationDTO(
                    url: "https://example.com/plan",
                    title: "Plan",
                    startIndex: 0,
                    endIndex: 5
                )],
                toolCalls: [ToolCallInfoDTO(
                    id: "tool_search",
                    type: .webSearch,
                    status: .completed,
                    code: nil,
                    results: ["Plan"],
                    queries: ["GlassGPT 5.1.2"]
                )],
                filePathAnnotations: [FilePathAnnotationDTO(
                    fileId: "file_plan",
                    containerId: "sandbox_1",
                    sandboxPath: "/tmp/beta-5-plan.md",
                    filename: "beta-5-plan.md",
                    startIndex: 6,
                    endIndex: 14
                )],
                agentTraceJSON: nil
            )
        ],
        runs: [makeChatRunSummary(id: runID, status: .completed, summary: "Done")]
    )
}

func makeAgentConversationDetailSnapshot(
    conversationID: String,
    runID: String,
    assistantContent: String
) throws -> ConversationDetailDTO {
    try ConversationDetailDTO(
        conversation: ConversationDTO(
            id: conversationID,
            title: "Agent Run",
            mode: .agent,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: runID,
            lastSyncCursor: "cur_agent_final"
        ),
        messages: [
            MessageDTO(
                id: "msg_agent_user",
                conversationID: conversationID,
                role: .user,
                content: "Run the council",
                thinking: nil,
                createdAt: .now,
                completedAt: .now,
                serverCursor: "cur_agent_user",
                runID: nil,
                annotations: nil,
                toolCalls: nil,
                filePathAnnotations: nil,
                agentTraceJSON: nil
            ),
            MessageDTO(
                id: "msg_agent_assistant",
                conversationID: conversationID,
                role: .assistant,
                content: assistantContent,
                thinking: nil,
                createdAt: .now,
                completedAt: .now,
                serverCursor: "cur_agent_assistant",
                runID: runID,
                annotations: [URLCitationDTO(
                    url: "https://example.com/report",
                    title: "Report",
                    startIndex: 0,
                    endIndex: 6
                )],
                toolCalls: [ToolCallInfoDTO(
                    id: "tool_exec",
                    type: .codeInterpreter,
                    status: .completed,
                    code: "print('ok')",
                    results: ["ok"],
                    queries: nil
                )],
                filePathAnnotations: [FilePathAnnotationDTO(
                    fileId: "file_report",
                    containerId: "sandbox_1",
                    sandboxPath: "/tmp/beta-5-report.md",
                    filename: "beta-5-report.md",
                    startIndex: 7,
                    endIndex: 15
                )],
                agentTraceJSON: encodeJSONString(makeAgentTurnTrace())
            )
        ],
        runs: [makeAgentRun(status: .completed, stage: .finalSynthesis, summary: "Complete")]
    )
}

func makeLiveProcessSnapshotJSONObject(
    activity: AgentProcessActivity,
    status: String,
    summary: String
) -> [String: Any] {
    let timestamp = iso8601String(for: .now)
    return [
        "activity": activity.rawValue,
        "currentFocus": "Review CI output",
        "leaderAcceptedFocus": "Review CI output",
        "leaderLiveStatus": status,
        "leaderLiveSummary": summary,
        "plan": [],
        "tasks": [],
        "decisions": [],
        "events": [],
        "evidence": [],
        "activeTaskIDs": ["task_ci"],
        "recentUpdates": [summary],
        "recentUpdateItems": [
            [
                "id": "update_review",
                "kind": "leaderPhase",
                "source": "leader",
                "phase": "leaderReview",
                "summary": summary,
                "createdAt": timestamp,
                "updatedAt": timestamp
            ]
        ],
        "recoveryState": "idle",
        "outcome": "",
        "updatedAt": timestamp
    ]
}

func makeLiveTaskJSONObject() -> [String: Any] {
    [
        "id": "task_ci",
        "owner": "workerA",
        "dependencyIDs": [],
        "title": "Check CI gates",
        "goal": "Verify all gates are green",
        "expectedOutput": "A concise CI status summary",
        "contextSummary": "Review the latest release lane",
        "toolPolicy": "enabled",
        "status": "running",
        "liveStatusText": "Inspecting logs",
        "liveSummary": "UI, backend, and release lanes are under review",
        "liveEvidence": ["UI shard passed", "Backend deploy healthy"],
        "liveConfidence": "high",
        "liveRisks": []
    ]
}

func makeAgentSuccessStreamEvents() throws -> [SSEEvent] {
    try [
        SSEEvent(
            event: "thinking_delta",
            data: makeJSONString(["thinkingDelta": "Leader is reviewing worker output"]),
            id: nil
        ),
        SSEEvent(
            event: "process_update",
            data: makeJSONString([
                "processSnapshot": makeLiveProcessSnapshotJSONObject(
                    activity: .reviewing,
                    status: "Leader reviewing",
                    summary: "Reviewing worker evidence"
                )
            ]),
            id: nil
        ),
        SSEEvent(
            event: "task_update",
            data: makeJSONString(["task": makeLiveTaskJSONObject()]),
            id: nil
        ),
        SSEEvent(
            event: "tool_call_update",
            data: makeJSONString([
                "toolCall": [
                    "id": "tool_exec",
                    "type": "code_interpreter",
                    "status": "interpreting",
                    "code": "print('ok')"
                ]
            ]),
            id: nil
        ),
        SSEEvent(
            event: "citations_update",
            data: makeJSONString([
                "citations": [
                    [
                        "url": "https://example.com/report",
                        "title": "Report",
                        "startIndex": 0,
                        "endIndex": 6
                    ]
                ]
            ]),
            id: nil
        ),
        SSEEvent(
            event: "file_path_annotations_update",
            data: makeJSONString([
                "filePathAnnotations": [
                    [
                        "fileId": "file_report",
                        "containerId": "sandbox_1",
                        "sandboxPath": "/tmp/beta-5-report.md",
                        "filename": "beta-5-report.md",
                        "startIndex": 7,
                        "endIndex": 15
                    ]
                ]
            ]),
            id: nil
        ),
        SSEEvent(
            event: "status",
            data: makeJSONString(["visibleSummary": "Synthesizing final answer"]),
            id: nil
        ),
        SSEEvent(
            event: "delta",
            data: makeJSONString(["textDelta": "Final synthesis body"]),
            id: nil
        ),
        SSEEvent(event: "done", data: "{}", id: nil)
    ]
}

func makeJSONString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try #require(String(data: data, encoding: .utf8))
}

func encodeJSONString(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return try #require(String(data: data, encoding: .utf8))
}

func iso8601String(for date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
