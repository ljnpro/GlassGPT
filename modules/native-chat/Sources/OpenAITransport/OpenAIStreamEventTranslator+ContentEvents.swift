import Foundation

extension OpenAIStreamEventTranslator {
    static func translateContentEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        if let event = translateResponseCreatedEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateTextDeltaEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateReasoningEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateAnnotationEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        return nil
    }

    static func translateResponseCreatedEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "response.created",
              let responseId = envelope.response?.id,
              !responseId.isEmpty else {
            return nil
        }
        return .responseCreated(responseId)
    }

    static func translateTextDeltaEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "response.output_text.delta",
              let delta = envelope.delta,
              !delta.isEmpty else {
            return nil
        }
        return .textDelta(delta)
    }

    static func translateReasoningEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        switch eventType {
        case "response.reasoning_summary_text.delta",
             "response.reasoning_text.delta":
            guard let delta = envelope.delta, !delta.isEmpty else { return nil }
            return .thinkingDelta(delta)

        case "response.reasoning_summary_text.done",
             "response.reasoning_text.done":
            return .thinkingFinished

        default:
            return nil
        }
    }

    static func translateAnnotationEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        guard eventType == "response.output_text.annotation.added",
              let annotation = envelope.annotation else {
            return nil
        }
        return annotationEvent(from: annotation)
    }
}
