import Foundation
import os

/// Translates raw SSE event frames into typed ``StreamEvent`` values.
///
/// This is a stateless translator that decodes each frame independently. For stateful
/// accumulation of stream content, see ``SSEEventDecoder``.
public enum OpenAIStreamEventTranslator {
    private static let logger = Logger(subsystem: "GlassGPT", category: "sse")

    /// Extracts the response identifier from a raw SSE event data payload.
    /// - Parameter data: The raw JSON data from the SSE frame.
    /// - Returns: The response identifier, or `nil` if not present.
    public static func extractResponseIdentifier(from data: Data) -> String? {
        guard let envelope = decodeEnvelope(from: data) else {
            return nil
        }
        return responseIdentifier(from: envelope)
    }

    /// Extracts the event sequence number from a raw SSE event data payload.
    /// - Parameter data: The raw JSON data from the SSE frame.
    /// - Returns: The sequence number, or `nil` if not present.
    public static func extractSequenceNumber(from data: Data) -> Int? {
        guard let envelope = decodeEnvelope(from: data) else {
            return nil
        }
        return envelope.sequenceNumber ?? envelope.response?.sequenceNumber
    }

    /// Translates a raw SSE event into a typed ``StreamEvent``.
    /// - Parameters:
    ///   - eventType: The SSE event type string.
    ///   - data: The raw JSON data from the SSE frame.
    /// - Returns: The translated stream event, or `nil` if the event type is not recognized.
    public static func translate(
        eventType: String,
        data: Data
    ) -> StreamEvent? {
        guard let envelope = decodeEnvelope(from: data) else {
            return nil
        }
        return translate(eventType: eventType, envelope: envelope)
    }

    private static func translate(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        if let event = translateContentEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateToolEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateTerminalEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if isIgnoredEventType(eventType) {
            return nil
        }
        return nil
    }

    private static func isIgnoredEventType(_ eventType: String) -> Bool {
        switch eventType {
        case "response.queued",
             "response.in_progress",
             "response.output_text.done",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            true

        default:
            false
        }
    }

    private static func decodeEnvelope(from data: Data) -> ResponsesStreamEnvelopeDTO? {
        do {
            return try JSONCoding.decode(ResponsesStreamEnvelopeDTO.self, from: data)
        } catch {
            logger.debug("Stream event envelope decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func responseIdentifier(from envelope: ResponsesStreamEnvelopeDTO) -> String? {
        if let responseID = envelope.response?.id, !responseID.isEmpty {
            return responseID
        }
        if let responseID = envelope.resolvedResponse.id, !responseID.isEmpty {
            return responseID
        }
        return nil
    }
}
