import BackendClient
import ChatDomain
import ChatProjectionPersistence
import Foundation

private struct DeltaPayload: Decodable {
    let textDelta: String?
}

private struct ThinkingDeltaPayload: Decodable {
    let thinkingDelta: String?
}

private struct StatusPayload: Decodable {
    let visibleSummary: String?
}

private struct ToolCallPayload: Decodable {
    let toolCall: ToolCallInfo
}

private struct CitationsPayload: Decodable {
    let citations: [URLCitation]
}

private struct FilePathAnnotationsPayload: Decodable {
    let filePathAnnotations: [FilePathAnnotation]
}

private struct ProcessUpdatePayload: Decodable {
    let processSnapshot: AgentProcessSnapshot
}

private struct TaskUpdatePayload: Decodable {
    let task: AgentTask
}

/// Describes whether an agent stream event should continue the active stream loop or terminate it.
package enum AgentStreamOutcome {
    case continueLoop
    case finish
}

@MainActor
package extension BackendAgentController {
    func beginAgentStream() {
        isRunning = true
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
    }

    func handleAgentStreamEvent(
        _ event: SSEEvent,
        conversationServerID: String,
        runID: String
    ) async throws -> AgentStreamOutcome {
        switch event.event {
        case "delta":
            applyAgentTextDelta(from: event)
            return .continueLoop
        case "thinking_delta":
            applyAgentThinkingDelta(from: event)
            return .continueLoop
        case "thinking_done":
            isThinking = false
            return .continueLoop
        case "tool_call_update":
            applyAgentToolCallUpdate(from: event)
            return .continueLoop
        case "citations_update":
            applyAgentCitationsUpdate(from: event)
            return .continueLoop
        case "file_path_annotations_update":
            applyAgentFilePathAnnotationsUpdate(from: event)
            return .continueLoop
        case "process_update":
            applyAgentProcessUpdate(from: event)
            return .continueLoop
        case "task_update":
            applyAgentTaskUpdate(from: event)
            return .continueLoop
        case "status":
            try await applyAgentStatus(from: event, runID: runID)
            return .continueLoop
        case "done":
            try await finalizeAgentStream(conversationServerID: conversationServerID)
            return .finish
        case "error":
            errorMessage = event.data
            return .finish
        default:
            try await refreshAgentProjection()
            return .continueLoop
        }
    }

    func applyAgentTextDelta(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(event, as: DeltaPayload.self),
              let textDelta = payload.textDelta
        else {
            return
        }
        currentStreamingText += textDelta
    }

    func applyAgentThinkingDelta(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(event, as: ThinkingDeltaPayload.self),
              let thinkingDelta = payload.thinkingDelta
        else {
            return
        }
        currentThinkingText += thinkingDelta
        isThinking = true
    }

    func applyAgentToolCallUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(event, as: ToolCallPayload.self) else {
            return
        }
        activeToolCalls.removeAll { $0.id == payload.toolCall.id }
        activeToolCalls.append(payload.toolCall)
    }

    func applyAgentCitationsUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(event, as: CitationsPayload.self) else {
            return
        }
        liveCitations = payload.citations
    }

    func applyAgentFilePathAnnotationsUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(event, as: FilePathAnnotationsPayload.self) else {
            return
        }
        liveFilePathAnnotations = payload.filePathAnnotations
    }

    func applyAgentProcessUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(
            event,
            as: ProcessUpdatePayload.self,
            configure: { $0.dateDecodingStrategy = .iso8601 }
        ) else {
            return
        }
        processSnapshot = payload.processSnapshot
    }

    func applyAgentTaskUpdate(from event: SSEEvent) {
        guard let payload = decodeAgentPayload(
            event,
            as: TaskUpdatePayload.self,
            configure: { $0.dateDecodingStrategy = .iso8601 }
        ) else {
            return
        }
        var snapshot = processSnapshot
        snapshot.tasks.removeAll { $0.id == payload.task.id }
        snapshot.tasks.append(payload.task)
        processSnapshot = snapshot
    }

    func applyAgentStatus(from event: SSEEvent, runID: String) async throws {
        guard let payload = decodeAgentPayload(event, as: StatusPayload.self),
              let summary = payload.visibleSummary
        else {
            return
        }

        if currentThinkingText.isEmpty {
            currentThinkingText = summary
        }
        isThinking = true

        try await refreshAgentProjection()

        let run = try await client.fetchRun(runID)
        lastRunSummary = run
        let synthesizedSnapshot = BackendConversationSupport.processSnapshot(
            for: run,
            progressLabel: summary
        )
        processSnapshot = mergeAgentProcessSnapshot(
            existing: processSnapshot,
            synthesized: synthesizedSnapshot
        )
    }

    func refreshAgentProjection() async throws {
        try await loader.applyIncrementalSync()
        try await refreshVisibleConversation()
    }

    func finalizeAgentStream(conversationServerID: String) async throws {
        try await setCurrentConversation(
            loader.refreshConversationDetail(serverID: conversationServerID)
        )
        syncVisibleState()
        clearAgentLiveSurface()
    }

    func finishAgentStreamAfterTermination(
        conversationServerID: String,
        selectionToken: UUID
    ) async {
        do {
            guard visibleSelectionToken == selectionToken else { return }
            try await setCurrentConversation(
                loader.refreshConversationDetail(serverID: conversationServerID)
            )
            syncVisibleState()
            clearAgentLiveSurface()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decodeAgentPayload<Payload: Decodable>(
        _ event: SSEEvent,
        as _: Payload.Type,
        configure: (inout JSONDecoder) -> Void = { _ in }
    ) -> Payload? {
        guard let payloadData = event.data.data(using: .utf8) else {
            return nil
        }

        var decoder = JSONDecoder()
        configure(&decoder)
        do {
            return try decoder.decode(Payload.self, from: payloadData)
        } catch {
            return nil
        }
    }
}
