import Foundation

public extension OpenAIResponseParser {
    /// Extracts the primary output text from a decoded Responses API payload.
    func extractOutputText(from response: ResponsesResponseDTO) -> String {
        OpenAIResponseOutputExtractor.extractOutputText(from: response) ?? ""
    }

    /// Extracts reasoning text from a decoded Responses API payload.
    func extractReasoningText(from response: ResponsesResponseDTO) -> String? {
        OpenAIResponseOutputExtractor.extractReasoningText(from: response)
    }
}
