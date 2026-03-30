import BackendClient
import ChatDomain
import Foundation

/// Shared stream-event projection behavior for backend conversation controllers.
@MainActor
package protocol BackendConversationStreamProjecting: BackendConversationRunStreamDriving {
    var currentStreamingText: String { get set }
    var currentThinkingText: String { get set }
    var activeToolCalls: [ToolCallInfo] { get set }
    var liveCitations: [URLCitation] { get set }
    var liveFilePathAnnotations: [FilePathAnnotation] { get set }
    var isThinking: Bool { get set }
    var errorMessage: String? { get set }

    func applyStreamStatusEvent(from event: SSEEvent)
    func applyStreamStageEvent(from event: SSEEvent)
    func applyModeSpecificStreamEvent(
        _ event: SSEEvent,
        conversationServerID: String,
        runID: String
    ) async throws -> BackendConversationStreamOutcome
}

@MainActor
package extension BackendConversationStreamProjecting {
    /// Resets shared live-stream projection state before the first SSE event arrives.
    func beginLiveStream() {
        isRunActive = true
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
    }

    /// Applies a buffered batch of non-terminal SSE events to shared live state.
    func flushLiveStreamBatch(
        _ batch: [SSEEvent],
        conversationServerID: String,
        runID: String
    ) async throws {
        var textDeltas: [String] = []
        var thinkingDeltas: [String] = []

        for event in batch {
            switch event.event {
            case "delta":
                if let delta = streamTextDelta(from: event) {
                    textDeltas.append(delta)
                }
            case "thinking_delta":
                if let delta = streamThinkingDelta(from: event) {
                    thinkingDeltas.append(delta)
                    isThinking = true
                }
            case "thinking_done":
                isThinking = false
            case "tool_call_update":
                applyStreamToolCallUpdate(from: event)
            case "citations_update":
                applyStreamCitationsUpdate(from: event)
            case "file_path_annotations_update":
                applyStreamFilePathAnnotationsUpdate(from: event)
            case "status":
                applyStreamStatusEvent(from: event)
            case "stage":
                applyStreamStageEvent(from: event)
            default:
                _ = try await applyModeSpecificStreamEvent(
                    event,
                    conversationServerID: conversationServerID,
                    runID: runID
                )
            }
        }

        if !textDeltas.isEmpty {
            currentStreamingText += textDeltas.joined()
        }
        if !thinkingDeltas.isEmpty {
            currentThinkingText += thinkingDeltas.joined()
        }
    }

    /// Handles a terminal or immediate SSE event and returns whether the run loop should finish.
    func handleLiveTerminalEvent(
        _ event: SSEEvent,
        conversationServerID: String,
        runID: String
    ) async throws -> BackendConversationStreamOutcome {
        switch event.event {
        case "delta":
            applyStreamTextDelta(from: event)
            return .continueLoop
        case "thinking_delta":
            applyStreamThinkingDelta(from: event)
            return .continueLoop
        case "thinking_done":
            isThinking = false
            return .continueLoop
        case "tool_call_update":
            applyStreamToolCallUpdate(from: event)
            return .continueLoop
        case "citations_update":
            applyStreamCitationsUpdate(from: event)
            return .continueLoop
        case "file_path_annotations_update":
            applyStreamFilePathAnnotationsUpdate(from: event)
            return .continueLoop
        case "status":
            applyStreamStatusEvent(from: event)
            return .continueLoop
        case "stage":
            applyStreamStageEvent(from: event)
            return .continueLoop
        case "done":
            let streamedContent = currentStreamingText
            let streamedThinking = currentThinkingText
            try await finalizeVisibleRun(conversationServerID: conversationServerID)
            applyStreamingFallbackIfNeeded(
                streamedContent: streamedContent,
                streamedThinking: streamedThinking
            )
            clearLiveSurface()
            return .finish
        case "error":
            errorMessage = streamErrorMessage(from: event)
            return .finish
        default:
            return try await applyModeSpecificStreamEvent(
                event,
                conversationServerID: conversationServerID,
                runID: runID
            )
        }
    }

    /// Clears the shared detached live surface after a run completes or is cancelled.
    func clearLiveSurface() {
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isThinking = false
    }

    /// Default mode-specific stream hook for controllers without extra event types.
    func applyModeSpecificStreamEvent(
        _: SSEEvent,
        conversationServerID _: String,
        runID _: String
    ) async throws -> BackendConversationStreamOutcome {
        .continueLoop
    }
}
