import Foundation

enum SSEEventTerminalResult {
    case continued
    case terminalCompleted
    case terminalIncomplete(String?)
    case terminalError
}

struct SSEEventDecoder {
    private(set) var accumulatedText = ""
    private(set) var accumulatedThinking = ""
    private(set) var accumulatedFilePathAnnotations: [FilePathAnnotation] = []
    private(set) var thinkingActive = false
    private(set) var emittedAnyOutput = false
    private(set) var sawTerminalEvent = false

    mutating func decode(
        frame: SSEFrame,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
        guard let jsonData = frame.data.data(using: .utf8) else {
            return .continued
        }

        let sequenceNumber = OpenAIStreamEventTranslator.extractSequenceNumber(from: jsonData)

        if let translated = OpenAIStreamEventTranslator.translate(eventType: frame.type, data: jsonData) {
            switch translated {
            case .textDelta(let delta):
                emittedAnyOutput = true
                accumulatedText += delta
                continuation.yield(.textDelta(delta))
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .thinkingDelta(let delta):
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
                yieldThinkingFinishedIfNeeded(continuation: continuation)
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .responseCreated(let responseId):
                continuation.yield(.responseCreated(responseId))
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                #if DEBUG
                Loggers.openAI.debug("[SSE] Response created: \(responseId)")
                #endif
                return .continued

            case .sequenceUpdate(_):
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .filePathAnnotationAdded(let annotation):
                accumulatedFilePathAnnotations.append(annotation)
                continuation.yield(.filePathAnnotationAdded(annotation))
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued

            case .completed(let fullText, let fullThinking, let filePathAnnotations):
                sawTerminalEvent = true
                updateTerminalState(
                    fullText: fullText,
                    fullThinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                )
                return .terminalCompleted

            case .incomplete(let fullText, let fullThinking, let filePathAnnotations, let message):
                sawTerminalEvent = true
                updateTerminalState(
                    fullText: fullText,
                    fullThinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                )
                return .terminalIncomplete(message)

            case .error(let error):
                sawTerminalEvent = true
                continuation.yield(.error(error))
                return .terminalError

            default:
                continuation.yield(translated)
                yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
                return .continued
            }
        }

        switch frame.type {
        case "response.output_text.done":
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
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        default:
            #if DEBUG
            Loggers.openAI.debug("[SSE] Unhandled event: \(frame.type)")
            #endif
            return .continued
        }
    }

    mutating func yieldThinkingFinishedIfNeeded(
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard thinkingActive else { return }
        thinkingActive = false
        continuation.yield(.thinkingFinished)
    }

    var terminalThinking: String? {
        accumulatedThinking.isEmpty ? nil : accumulatedThinking
    }

    var terminalFilePathAnnotations: [FilePathAnnotation]? {
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

    private func decodeEnvelope(from data: Data) -> ResponsesStreamEnvelopeDTO? {
        do {
            return try JSONCoding.decode(ResponsesStreamEnvelopeDTO.self, from: data)
        } catch {
            return nil
        }
    }
}
