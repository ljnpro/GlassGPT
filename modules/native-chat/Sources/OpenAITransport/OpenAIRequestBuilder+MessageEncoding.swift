import Foundation

public extension OpenAIRequestBuilder {
    /// Converts an array of API messages into the DTO format expected by the Responses API.
    /// - Parameter messages: The messages to convert.
    /// - Returns: An array of input message DTOs.
    static func buildInputMessages(messages: [APIMessage]) -> [ResponsesInputMessageDTO] {
        OpenAIRequestFactory.buildInputMessages(messages: messages)
    }

    /// Returns the MIME type for the given filename based on its extension.
    /// - Parameter filename: The filename to inspect.
    /// - Returns: The corresponding MIME type string.
    static func mimeType(for filename: String) -> String {
        OpenAIRequestFactory.mimeType(for: filename)
    }
}
