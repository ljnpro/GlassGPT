import Foundation

public extension OpenAIRequestBuilder {
    /// Builds a request for generating a conversation title.
    /// - Parameters:
    ///   - conversationPreview: A preview of the conversation text to summarize.
    ///   - apiKey: The API key for authentication.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func titleRequest(conversationPreview: String, apiKey: String) throws -> URLRequest {
        try requestFactory.titleRequest(
            conversationPreview: conversationPreview,
            apiKey: apiKey
        )
    }

    /// Builds a request for cancelling an in-progress response.
    /// - Parameters:
    ///   - responseId: The API response identifier to cancel.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func cancelRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        try requestFactory.cancelRequest(
            responseID: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for fetching a completed response by ID.
    /// - Parameters:
    ///   - responseId: The API response identifier to fetch.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func fetchRequest(responseId: String, apiKey: String, useDirectBaseURL: Bool) throws -> URLRequest {
        try requestFactory.fetchRequest(
            responseID: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for listing available models.
    /// - Parameter apiKey: The API key for authentication.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func modelsRequest(apiKey: String) throws -> URLRequest {
        try requestFactory.modelsRequest(apiKey: apiKey)
    }
}
