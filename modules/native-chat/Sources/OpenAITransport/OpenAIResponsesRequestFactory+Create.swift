import ChatDomain
import Foundation

public extension OpenAIRequestFactory {
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
        let timeoutInterval = configuration.chatRequestTimeoutInterval
        let resolvedTools = tools ?? Self.defaultChatTools()
        let body = try JSONCoding.encode(
            ResponsesCreateRequestDTO(
                model: modelIdentifier,
                instructions: instructions,
                previousResponseID: previousResponseID,
                input: input,
                stream: stream,
                store: store,
                serviceTier: serviceTier?.rawValue,
                tools: resolvedTools,
                background: background,
                reasoning: reasoningEffort.map {
                    ResponsesReasoningRequestDTO(
                        effort: $0.rawValue,
                        summary: "auto"
                    )
                },
                maxOutputTokens: maxOutputTokens
            )
        )

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/responses",
                method: "POST",
                accept: stream ? "text/event-stream" : "application/json",
                timeoutInterval: timeoutInterval
            ),
            apiKey: apiKey,
            body: body,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}
