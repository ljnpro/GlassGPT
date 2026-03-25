import ChatDomain
import Foundation

public extension OpenAIRequestBuilder {
    /// Builds a generic Responses API create request.
    func responseRequest(
        apiKey: String,
        modelIdentifier: String,
        input: [ResponsesInputMessageDTO],
        instructions: String? = nil,
        previousResponseID: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        serviceTier: ServiceTier? = nil,
        tools: [ResponsesToolDTO]? = nil,
        background: Bool? = nil,
        maxOutputTokens: Int? = nil,
        stream: Bool,
        store: Bool? = true,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try requestFactory.responseRequest(
            apiKey: apiKey,
            modelIdentifier: modelIdentifier,
            input: input,
            instructions: instructions,
            previousResponseID: previousResponseID,
            reasoningEffort: reasoningEffort,
            serviceTier: serviceTier,
            tools: tools,
            background: background,
            maxOutputTokens: maxOutputTokens,
            stream: stream,
            store: store,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}
