import Foundation

extension OpenAIStreamEventTranslator {
    static func translateToolEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        if let event = translateWebSearchEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateCodeInterpreterEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        if let event = translateFileSearchEvent(eventType: eventType, envelope: envelope) {
            return event
        }
        return nil
    }

    static func translateWebSearchEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        switch eventType {
        case "response.web_search_call.in_progress":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .webSearchStarted(itemId)

        case "response.web_search_call.searching":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .webSearchSearching(itemId)

        case "response.web_search_call.completed":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .webSearchCompleted(itemId)

        default:
            return nil
        }
    }

    static func translateCodeInterpreterEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        switch eventType {
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

        default:
            return nil
        }
    }

    static func translateFileSearchEvent(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO
    ) -> StreamEvent? {
        switch eventType {
        case "response.file_search_call.in_progress":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .fileSearchStarted(itemId)

        case "response.file_search_call.searching":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .fileSearchSearching(itemId)

        case "response.file_search_call.completed":
            guard let itemId = envelope.itemID, !itemId.isEmpty else { return nil }
            return .fileSearchCompleted(itemId)

        default:
            return nil
        }
    }
}
