import ChatDomain
import Foundation
import os

/// The result of processing an SSE frame, indicating whether the stream should continue.
public enum SSEEventTerminalResult {
    /// The frame was processed and the stream should continue.
    case continued
    /// A terminal "completed" event was received.
    case terminalCompleted
    /// A terminal "incomplete" event was received with an optional message.
    case terminalIncomplete(String?)
    /// A terminal error event was received.
    case terminalError
}

private let sseDecoderSignposter = OSSignposter(subsystem: "GlassGPT", category: "streaming")

/// Stateful decoder that processes SSE frames, accumulates content, and emits ``StreamEvent`` values.
///
/// Tracks accumulated text, thinking content, response IDs, and terminal states across
/// the lifetime of a single streaming session.
public struct SSEEventDecoder {
    static let logger = Logger(subsystem: "GlassGPT", category: "sse")
    /// The accumulated output text from all text deltas.
    public internal(set) var accumulatedText = ""
    /// The accumulated reasoning/thinking text.
    public internal(set) var accumulatedThinking = ""
    /// File path annotations accumulated during the stream.
    public internal(set) var accumulatedFilePathAnnotations: [FilePathAnnotation] = []
    /// Whether the model is currently in its thinking phase.
    public internal(set) var thinkingActive = false
    /// Whether any output (text or thinking) has been emitted.
    public internal(set) var emittedAnyOutput = false
    /// Whether a terminal event (completed, incomplete, or error) has been received.
    public internal(set) var sawTerminalEvent = false
    /// The response ID that has been emitted, if any.
    public internal(set) var emittedResponseID: String?
    /// The number of malformed frames seen in a row.
    var consecutiveDecodeFailures = 0

    /// Creates a new empty SSE event decoder.
    public init() {}

    /// Decodes a single SSE frame, emitting stream events and returning the terminal status.
    /// - Parameters:
    ///   - frame: The SSE frame to decode.
    ///   - continuation: The async stream continuation to yield events to.
    /// - Returns: The terminal result indicating whether the stream should continue.
    public mutating func decode(
        frame: SSEFrame,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
        let signpostID = sseDecoderSignposter.makeSignpostID()
        let signpostState = sseDecoderSignposter.beginInterval("DecodeSSEFrame", id: signpostID)
        defer { sseDecoderSignposter.endInterval("DecodeSSEFrame", signpostState) }

        guard let jsonData = frame.data.data(using: .utf8) else {
            recordDecodeFailure("SSE frame data is not valid UTF-8.")
            return .continued
        }

        let sequenceNumber = OpenAIStreamEventTranslator.extractSequenceNumber(from: jsonData)
        let responseID = OpenAIStreamEventTranslator.extractResponseIdentifier(from: jsonData)

        if let translated = OpenAIStreamEventTranslator.translate(eventType: frame.type, data: jsonData) {
            resetDecodeFailures()
            return handleTranslatedEvent(
                translated,
                responseID: responseID,
                sequenceNumber: sequenceNumber,
                continuation: continuation
            )
        }

        return handleUntranslatedFrame(
            frameType: frame.type,
            jsonData: jsonData,
            responseID: responseID,
            sequenceNumber: sequenceNumber,
            continuation: continuation
        )
    }

    /// Emits a thinking-finished event if thinking is currently active, then deactivates thinking.
    /// - Parameter continuation: The async stream continuation to yield the event to.
    public mutating func yieldThinkingFinishedIfNeeded(
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard thinkingActive else { return }
        thinkingActive = false
        continuation.yield(.thinkingFinished)
    }

    /// The accumulated thinking text for terminal events, or `nil` if empty.
    public var terminalThinking: String? {
        accumulatedThinking.isEmpty ? nil : accumulatedThinking
    }

    /// The accumulated file path annotations for terminal events, or `nil` if empty.
    public var terminalFilePathAnnotations: [FilePathAnnotation]? {
        accumulatedFilePathAnnotations.isEmpty ? nil : accumulatedFilePathAnnotations
    }
}
