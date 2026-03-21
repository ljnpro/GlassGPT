import ChatDomain
import Foundation

public extension OpenAIRequestBuilder {
    /// Builds a streaming chat completion request.
    /// - Parameters:
    ///   - apiKey: The API key for authentication.
    ///   - messages: The conversation messages.
    ///   - model: The model to use.
    ///   - reasoningEffort: The reasoning effort level.
    ///   - backgroundModeEnabled: Whether background mode is enabled.
    ///   - serviceTier: The service tier for the request.
    ///   - vectorStoreIds: Optional vector store IDs for file search.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request for streaming.
    /// - Throws: ``OpenAIServiceError`` if URL or body encoding fails.
    func streamingRequest(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = [],
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try requestFactory.streamingRequest(
            apiKey: apiKey,
            messages: messages,
            model: model,
            reasoningEffort: reasoningEffort,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTier: serviceTier,
            vectorStoreIds: vectorStoreIds,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a streaming recovery request to resume from a given sequence number.
    /// - Parameters:
    ///   - responseId: The API response identifier to resume.
    ///   - startingAfter: The sequence number to resume after.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request for stream recovery.
    /// - Throws: ``OpenAIServiceError`` if URL construction fails.
    func recoveryRequest(
        responseId: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool
    ) throws(OpenAIServiceError) -> URLRequest {
        try requestFactory.recoveryRequest(
            responseID: responseId,
            startingAfter: startingAfter,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}
