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
    private(set) var emittedResponseID: String?

    mutating func decode(
        frame: SSEFrame,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
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
                #if DEBUG
                Loggers.openAI.debug("[SSE] Response created: \(responseId)")
                #endif
                return .continued

            case .sequenceUpdate(_):
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
            return nil
        }
    }
}
