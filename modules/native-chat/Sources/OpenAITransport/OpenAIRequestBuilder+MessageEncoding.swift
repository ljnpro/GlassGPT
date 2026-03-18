import Foundation

public extension OpenAIRequestBuilder {
    static func buildInputMessages(messages: [APIMessage]) -> [ResponsesInputMessageDTO] {
        OpenAIRequestFactory.buildInputMessages(messages: messages)
    }

    static func mimeType(for filename: String) -> String {
        OpenAIRequestFactory.mimeType(for: filename)
    }
}
