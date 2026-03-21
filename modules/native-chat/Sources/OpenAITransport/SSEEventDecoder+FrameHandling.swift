import ChatDomain
import Foundation

extension SSEEventDecoder {
    mutating func handleUntranslatedFrame(
        frameType: String,
        jsonData: Data,
        responseID: String?,
        sequenceNumber: Int?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
        switch frameType {
        case "response.output_text.done":
            return handleOutputTextDone(
                frameType: frameType,
                jsonData: jsonData,
                responseID: responseID,
                sequenceNumber: sequenceNumber,
                continuation: continuation
            )

        case "response.queued",
             "response.in_progress",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            resetDecodeFailures()
            yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
            yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
            return .continued

        default:
            return handleUnknownFrame(frameType: frameType, jsonData: jsonData)
        }
    }

    mutating func handleOutputTextDone(
        frameType: String,
        jsonData: Data,
        responseID: String?,
        sequenceNumber: Int?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) -> SSEEventTerminalResult {
        yieldResponseIdentifierIfNeeded(responseID, continuation: continuation)
        if let envelope = decodeEnvelope(from: jsonData),
           let fullText = envelope.text,
           !fullText.isEmpty {
            resetDecodeFailures()
            accumulatedText = fullText
            if let itemID = envelope.itemID {
                activeTextItemID = itemID
            }
            emittedAnyOutput = true
        } else {
            recordDecodeFailure("SSE frame could not be decoded for event type \(frameType).")
        }
        yieldSequenceIfNeeded(sequenceNumber, continuation: continuation)
        return .continued
    }

    mutating func handleUnknownFrame(
        frameType: String,
        jsonData: Data
    ) -> SSEEventTerminalResult {
        if decodeEnvelope(from: jsonData) == nil {
            recordDecodeFailure("SSE frame could not be decoded for event type \(frameType).")
        } else {
            resetDecodeFailures()
        }
        return .continued
    }

    func yieldSequenceIfNeeded(
        _ sequenceNumber: Int?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard let sequenceNumber else { return }
        continuation.yield(.sequenceUpdate(sequenceNumber))
    }

    mutating func yieldResponseIdentifierIfNeeded(
        _ responseID: String?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard let responseID, !responseID.isEmpty, responseID != emittedResponseID else { return }
        emittedResponseID = responseID
        continuation.yield(.responseCreated(responseID))
    }

    func decodeEnvelope(from data: Data) -> ResponsesStreamEnvelopeDTO? {
        do {
            return try JSONCoding.decode(ResponsesStreamEnvelopeDTO.self, from: data)
        } catch {
            return nil
        }
    }

    mutating func resetDecodeFailures() {
        consecutiveDecodeFailures = 0
    }

    mutating func recordDecodeFailure(_ message: String) {
        consecutiveDecodeFailures += 1
        if shouldLogDecodeFailure(after: consecutiveDecodeFailures) {
            Self.logger.error("\(message, privacy: .public)")
        }
    }

    func shouldLogDecodeFailure(after count: Int) -> Bool {
        count == Self.decodeFailureLogThreshold
    }
}
