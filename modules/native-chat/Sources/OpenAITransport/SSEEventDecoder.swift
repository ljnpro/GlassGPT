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
    private static let logger = Logger(subsystem: "GlassGPT", category: "sse")
    /// The accumulated output text from all text deltas.
    public private(set) var accumulatedText = ""
    /// The accumulated reasoning/thinking text.
    public private(set) var accumulatedThinking = ""
    /// File path annotations accumulated during the stream.
    public private(set) var accumulatedFilePathAnnotations: [FilePathAnnotation] = []
    /// Whether the model is currently in its thinking phase.
    public private(set) var thinkingActive = false
    /// Whether any output (text or thinking) has been emitted.
    public private(set) var emittedAnyOutput = false
    /// Whether a terminal event (completed, incomplete, or error) has been received.
    public private(set) var sawTerminalEvent = false
    /// The response ID that has been emitted, if any.
    public private(set) var emittedResponseID: String?

    /// Creates a new empty SSE event decoder.
    public init() {}

    /// Decodes a single SSE frame, emitting stream events and returning the terminal status.
    /// - Parameters:
    ///   - frame: The SSE frame to decode.
    ///   - continuation: The async stream continuation to yield events to.
    /// - Returns: The terminal result indicating whether the stream should continue.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public mutating func decode(
        frame: SSEFrame,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
        let signpostID = sseDecoderSignposter.makeSignpostID()
        let signpostState = sseDecoderSignposter.beginInterval("DecodeSSEFrame", id: signpostID)
        defer { sseDecoderSignposter.endInterval("DecodeSSEFrame", signpostState) }

        guard let jsonData = frame.data.data(using: .utf8) else {
            return .continued
        }

        let sequenceNumber = OpenAIStreamEventTranslator.extractSequenceNumber(from: jsonData)
        let responseID = OpenAIStreamEventTranslator.extractResponseIdentifier(from: jsonData)

        if let translated = OpenAIStreamEventTranslator.translate(eventType: frame.type, data: jsonData) {
            switch translated {
            case .textDelta(let delta):
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .thinkingDelta(let delta):
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                if !thinkingActive {
                    thinkingActive = true
                    continuation.yield(.thinkingStarted)
                }
                emittedAnyOutput = true
                accumulatedThinking += delta
                continuation.yield(.thinkingDelta(delta))
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .thinkingFinished:
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                yieldThinkingFinishedIfNeeded(continuation: continuation)
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .responseCreated(let responseId):
                yieldResponseIdentifierIfNeeded(responseId, continuation: continuation)
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .sequenceUpdate:
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .filePathAnnotationAdded(let annotation):
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                accumulatedFilePathAnnotations.append(annotation)
                continuation.yield(.filePathAnnotationAdded(annotation))
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .completed(let fullText, let fullThinking, let filePathAnnotations):
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                sawTerminalEvent = true
                updateTerminalState(
                    fullText: fullText,
                    fullThinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                )
                return .terminalCompleted

            case .incomplete(let fullText, let fullThinking, let filePathAnnotations, let message):
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                sawTerminalEvent = true
                updateTerminalState(
                    fullText: fullText,
                    fullThinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                )
                return .terminalIncomplete(message)

            case .error(let error):
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                sawTerminalEvent = true
                continuation.yield(.error(error))
                return .terminalError

            default:
                yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
                continuation.yield(translated)
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued
            }
        }

        switch frame.type {
        case "response.output_text.done":
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            if let envelope = decodeEnvelope(from: jsonData),
               let fullText = envelope.text,
               !fullText.isEmpty {
                accumulatedText = fullText
                emittedAnyOutput = true
            }
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        case "response.queued",
             "response.in_progress",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        default:
            return .continued
        }
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

    private mutating func updateTerminalState(
        fullText: String,
        fullThinking: String?,
        filePathAnnotations: [FilePathAnnotation]?
    ) {
        if !fullText.isEmpty {
            accumulatedText = fullText
        }
        if let fullThinking, !fullThinking.isEmpty {
            accumulatedThinking = fullThinking
        }
        if let filePathAnnotations, !filePathAnnotations.isEmpty {
            accumulatedFilePathAnnotations = filePathAnnotations
        }
        emittedAnyOutput = emittedAnyOutput || !accumulatedText.isEmpty || !accumulatedThinking.isEmpty
    }

    private func yieldSequenceIfNeeded(
        _ sequenceNumber: Int?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard let sequenceNumber else { return }
        continuation.yield(.sequenceUpdate(sequenceNumber))
    }

    private mutating func yieldResponseIdentifierIfNeeded(
        _ responseID: String?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard let responseID, !responseID.isEmpty, responseID != emittedResponseID else { return }
        emittedResponseID = responseID
        continuation.yield(.responseCreated(responseID))
    }

    private func decodeEnvelope(from data: Data) -> ResponsesStreamEnvelopeDTO? {
        do {
            return try JSONCoding.decode(ResponsesStreamEnvelopeDTO.self, from: data)
        } catch {
            Self.logger.debug("SSE envelope decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
