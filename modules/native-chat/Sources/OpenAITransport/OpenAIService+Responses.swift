import ChatDomain
import Foundation

public extension OpenAIService {
    /// Creates a non-streaming Responses API response.
    func createResponse(
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
        useDirectBaseURL: Bool = false
    ) async throws(OpenAIServiceError) -> ResponsesResponseDTO {
        let request = try requestBuilder.responseRequest(
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
            stream: false,
            store: true,
            useDirectBaseURL: useDirectBaseURL
        )

        let (data, response) = try await transport.data(for: request)
        return try responseParser.parseResponseDTO(data: data, response: response)
    }

    /// Starts a streaming Responses API request using generic create parameters.
    func streamResponse(
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
        useDirectBaseURL: Bool = false
    ) -> AsyncStream<StreamEvent> {
        cancelStream()

        let request: URLRequest
        do {
            request = try requestBuilder.responseRequest(
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
                stream: true,
                store: true,
                useDirectBaseURL: useDirectBaseURL
            )
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.requestFailed("Failed to encode request")))
                continuation.finish()
            }
        }

        return streamClient.makeStream(request: request)
    }
}
