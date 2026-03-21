import ChatDomain
import Foundation

extension SSEEventDecoder {
    mutating func updateTerminalState(
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

    mutating func handleTranslatedEvent(
        _ translated: StreamEvent,
        responseID: String?,
        sequenceNumber: Int?,
        itemID: String?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
        switch translated {
        case let .textDelta(delta):
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            emittedAnyOutput = true
            continuation.yield(textEvent(delta: delta, itemID: itemID))
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        case let .replaceText(text):
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            emittedAnyOutput = true
            accumulatedText = text
            continuation.yield(.replaceText(text))
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        case let .thinkingDelta(delta):
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

        case let .responseCreated(responseId):
            yieldResponseIdentifierIfNeeded(responseId, continuation: continuation)
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        case .sequenceUpdate:
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        case let .filePathAnnotationAdded(annotation):
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            accumulatedFilePathAnnotations.append(annotation)
            continuation.yield(.filePathAnnotationAdded(annotation))
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        case let .completed(fullText, fullThinking, filePathAnnotations):
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            sawTerminalEvent = true
            updateTerminalState(
                fullText: fullText,
                fullThinking: fullThinking,
                filePathAnnotations: filePathAnnotations
            )
            return .terminalCompleted

        case let .incomplete(fullText, fullThinking, filePathAnnotations, message):
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            sawTerminalEvent = true
            updateTerminalState(
                fullText: fullText,
                fullThinking: fullThinking,
                filePathAnnotations: filePathAnnotations
            )
            return .terminalIncomplete(message)

        case let .error(error):
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

    mutating func textEvent(delta: String, itemID: String?) -> StreamEvent {
        guard let itemID, !itemID.isEmpty else {
            accumulatedText += delta
            return .textDelta(delta)
        }

        defer { activeTextItemID = itemID }

        guard let activeTextItemID else {
            accumulatedText += delta
            return .textDelta(delta)
        }

        guard activeTextItemID != itemID else {
            accumulatedText += delta
            return .textDelta(delta)
        }

        accumulatedText = delta
        return .replaceText(delta)
    }
}
