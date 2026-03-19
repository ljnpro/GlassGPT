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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func translate(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        switch eventType {
        case "response.created":
            guard let responseId = envelope.response?.id, !responseId.isEmpty else {
                return nil
            }
            return .responseCreated(responseId)

        case "response.output_text.delta":
            guard let delta = envelope.delta, !delta.isEmpty else { return nil }
            return .textDelta(delta)

        case "response.reasoning_summary_text.delta",
             "response.reasoning_text.delta":
            guard let delta = envelope.delta, !delta.isEmpty else { return nil }
            return .thinkingDelta(delta)

        case "response.reasoning_summary_text.done",
             "response.reasoning_text.done":
            return .thinkingFinished

        case "response.web_search_call.in_progress":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .webSearchStarted(itemId)

        case "response.web_search_call.searching":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .webSearchSearching(itemId)

        case "response.web_search_call.completed":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .webSearchCompleted(itemId)

        case "response.code_interpreter_call.in_progress":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .codeInterpreterStarted(itemId)

        case "response.code_interpreter_call.interpreting":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .codeInterpreterInterpreting(itemId)

        case "response.code_interpreter_call_code.delta":
            guard let itemId = envelope.itemID, let delta = envelope.delta else { return nil }
            return .codeInterpreterCodeDelta(itemId, delta)

        case "response.code_interpreter_call_code.done":
            guard let itemId = envelope.itemID, let code = envelope.code else { return nil }
            return .codeInterpreterCodeDone(itemId, code)

        case "response.code_interpreter_call.completed":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .codeInterpreterCompleted(itemId)

        case "response.file_search_call.in_progress":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .fileSearchStarted(itemId)

        case "response.file_search_call.searching":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .fileSearchSearching(itemId)

        case "response.file_search_call.completed":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .fileSearchCompleted(itemId)

        case "response.output_text.annotation.added":
            guard let annotation = envelope.annotation else { return nil }
            return annotationEvent(from: annotation)

        case "response.completed":
            let response = envelope.resolvedResponse
            return .completed(
                extractOutputText(from: response) ?? "",
                extractReasoningText(from: response),
                extractFilePathAnnotations(from: response)
            )

        case "response.incomplete":
            let response = envelope.resolvedResponse
            return .incomplete(
                extractOutputText(from: response) ?? "",
                extractReasoningText(from: response),
                extractFilePathAnnotations(from: response),
                extractErrorMessage(from: response)
            )

        case "response.failed":
            let response = envelope.resolvedResponse
            if let message = extractErrorMessage(from: response), !message.isEmpty {
                return .error(.requestFailed(message))
            }
            return .error(.requestFailed("Response generation failed."))

        case "error":
            if let message = extractErrorMessage(from: envelope.resolvedResponse), !message.isEmpty {
                return .error(.requestFailed(message))
            }
            return .error(.requestFailed("Unknown streaming error."))

        case "response.queued",
             "response.in_progress",
             "response.output_text.done",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            return nil

        default:
            return nil
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
