import ChatDomain
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

    /// Extracts the output text from a completed response.
    /// - Parameter response: The response DTO.
    /// - Returns: The concatenated output text, or `nil` if none is present.
    public static func extractOutputText(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseTerminalExtraction.extractOutputText(from: response)
    }

    /// Extracts the reasoning/thinking text from a completed response.
    /// - Parameter response: The response DTO.
    /// - Returns: The concatenated reasoning text, or `nil` if none is present.
    public static func extractReasoningText(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseTerminalExtraction.extractReasoningText(from: response)
    }

    /// Extracts file path annotations from a completed response.
    /// - Parameter response: The response DTO.
    /// - Returns: An array of file path annotations found in the response.
    public static func extractFilePathAnnotations(from response: ResponsesResponseDTO) -> [FilePathAnnotation] {
        OpenAIResponseTerminalExtraction.extractFilePathAnnotations(from: response)
    }

    /// Extracts the error message from a failed or incomplete response.
    /// - Parameter response: The response DTO.
    /// - Returns: The error message, or `nil` if none is present.
    public static func extractErrorMessage(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseTerminalExtraction.extractErrorMessage(from: response)
    }

    /// Converts an annotation DTO into a stream event for URL citations or file path annotations.
    /// - Parameter annotation: The annotation DTO to convert.
    /// - Returns: A stream event, or `nil` if the annotation type is not supported.
    public static func annotationEvent(from annotation: ResponsesAnnotationDTO) -> StreamEvent? {
        OpenAIResponseAnnotationTranslator.annotationEvent(from: annotation)
    }

    /// Checks whether the given annotation type represents a file citation.
    /// - Parameter type: The annotation type string.
    /// - Returns: `true` if this is a file path or container file citation annotation.
    public static func isFileCitationAnnotationType(_ type: String) -> Bool {
        OpenAIResponseAnnotationTranslator.isFileCitationAnnotationType(type)
    }

    /// Extracts a substring from the given text using character-level indices.
    /// - Parameters:
    ///   - text: The source text.
    ///   - startIndex: The start character index.
    ///   - endIndex: The end character index (exclusive).
    /// - Returns: The extracted substring, or an empty string if indices are out of bounds.
    public static func extractAnnotatedSubstring(
        from text: String,
        startIndex: Int,
        endIndex: Int
    ) -> String {
        OpenAIResponseAnnotationTranslator.extractAnnotatedSubstring(
            from: text,
            startIndex: startIndex,
            endIndex: endIndex
        )
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

    static func extractOutputText(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseOutputExtractor.extractOutputText(from: response)
    }

    static func extractReasoningText(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseOutputExtractor.extractReasoningText(from: response)
    }

    static func extractFilePathAnnotations(from response: ResponsesResponseDTO) -> [FilePathAnnotation] {
        OpenAIResponseOutputExtractor.extractFilePathAnnotations(from: response)
    }

    static func extractErrorMessage(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseOutputExtractor.extractErrorMessage(from: response)
    }

    static func preferredMessageItems(from response: ResponsesResponseDTO) -> [ResponsesOutputItemDTO] {
        OpenAIResponseOutputExtractor.preferredMessageItems(from: response)
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
