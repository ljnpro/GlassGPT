import Foundation

extension OpenAIStreamEventTranslator {
    static func translateTerminalEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        if let event = translateCompletedEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateIncompleteEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateFailedEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateErrorEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        return nil
    }

    static func translateCompletedEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "response.completed" else { return nil }
        let response = envelope.resolvedResponse
        return .completed(
            extractOutputText(from: response) ?? "",
            extractReasoningText(from: response),
            extractFilePathAnnotations(from: response)
        )
    }

    static func translateIncompleteEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "response.incomplete" else { return nil }
        let response = envelope.resolvedResponse
        return .incomplete(
            extractOutputText(from: response) ?? "",
            extractReasoningText(from: response),
            extractFilePathAnnotations(from: response),
            extractErrorMessage(from: response)
        )
    }

    static func translateFailedEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "response.failed" else { return nil }
        let response = envelope.resolvedResponse
        if let message = extractErrorMessage(from: response), !message.isEmpty {
            return .error(.requestFailed(message))
        }
        return .error(.requestFailed("Response generation failed."))
    }

    static func translateErrorEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "error" else { return nil }
        if let message = extractErrorMessage(from: envelope.resolvedResponse), !message.isEmpty {
            return .error(.requestFailed(message))
        }
        return .error(.requestFailed("Unknown streaming error."))
    }
}
