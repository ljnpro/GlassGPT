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
    /// - Returns: A configured URL request for streaming.
    /// - Throws: If URL or body encoding fails.
    func streamingRequest(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = []
    ) throws -> URLRequest {
        try requestFactory.streamingRequest(
            apiKey: apiKey,
            messages: messages,
            model: model,
            reasoningEffort: reasoningEffort,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTier: serviceTier,
            vectorStoreIds: vectorStoreIds
        )
    }

    /// Builds a streaming recovery request to resume from a given sequence number.
    /// - Parameters:
    ///   - responseId: The API response identifier to resume.
    ///   - startingAfter: The sequence number to resume after.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request for stream recovery.
    /// - Throws: If URL construction fails.
    func recoveryRequest(
        responseId: String,
        startingAfter: Int,
        apiKey: String,
        useDirectBaseURL: Bool
    ) throws -> URLRequest {
        try requestFactory.recoveryRequest(
            responseID: responseId,
            startingAfter: startingAfter,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}
