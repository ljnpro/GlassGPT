import BackendContracts
import ChatDomain
import Foundation

/// Payload for standard streamed assistant text deltas.
package struct StreamTextDeltaPayload: Decodable {
    let textDelta: String?
}

/// Payload for streamed reasoning/thinking text deltas.
package struct StreamThinkingDeltaPayload: Decodable {
    let thinkingDelta: String?
}

/// Payload for streamed visible status updates.
package struct StreamStatusPayload: Decodable {
    let visibleSummary: String?
}

/// Payload for streamed stage summaries shared by chat and agent modes.
package struct StreamStagePayload: Decodable {
    let visibleSummary: String?
}

/// Payload for agent-specific streamed stage updates.
package struct AgentStreamStagePayload: Decodable {
    let stage: AgentStageDTO?
    let visibleSummary: String?
}

/// Payload for streamed tool-call updates.
package struct StreamToolCallPayload: Decodable {
    let toolCall: ToolCallInfo
}

/// Payload for streamed citation updates.
package struct StreamCitationsPayload: Decodable {
    let citations: [URLCitation]
}

/// Payload for streamed file-path annotation updates.
package struct StreamFilePathAnnotationsPayload: Decodable {
    let filePathAnnotations: [FilePathAnnotation]
}

/// Payload for streamed non-terminal or terminal error updates.
package struct StreamErrorPayload: Decodable {
    let code: String?
    let message: String?
    let phase: String?
}

/// Payload for agent process-card updates emitted during streaming.
package struct AgentProcessUpdatePayload: Decodable {
    let processSnapshot: AgentProcessSnapshot
}

/// Payload for agent task-board updates emitted during streaming.
package struct AgentTaskUpdatePayload: Decodable {
    let task: AgentTask
}
