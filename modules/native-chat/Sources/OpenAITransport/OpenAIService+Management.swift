import Foundation

public extension OpenAIService {
    /// Cancels the currently active streaming session, if any.
    func cancelStream() {
        streamClient.cancel()
    }

    /// Cancels an in-progress response on the API, with gateway fallback.
    /// - Parameters:
    ///   - responseId: The API response identifier to cancel.
    ///   - apiKey: The API key for authentication.
    /// - Throws: ``OpenAIServiceError`` if cancellation fails on all routes.
    func cancelResponse(responseId: String, apiKey: String) async throws(OpenAIServiceError) {
        do {
            try await cancelResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: false
            )
        } catch {
            guard requestBuilder.configuration.usesGatewayRouting else {
                throw error
            }

            try await cancelResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: true
            )
        }
    }

    /// Generates a short conversation title from a preview of the conversation text.
    /// - Parameters:
    ///   - conversationPreview: A preview of the conversation text.
    ///   - apiKey: The API key for authentication.
    /// - Returns: The generated title string.
    /// - Throws: ``OpenAIServiceError`` if title generation fails.
    func generateTitle(for conversationPreview: String, apiKey: String) async throws(OpenAIServiceError) -> String {
        let request = try requestBuilder.titleRequest(
            conversationPreview: conversationPreview,
            apiKey: apiKey
        )
        let (data, response) = try await transport.data(for: request)
        return try responseParser.parseGeneratedTitle(data: data, response: response)
    }

    /// Fetches a completed response by ID, with gateway fallback.
    /// - Parameters:
    ///   - responseId: The API response identifier to fetch.
    ///   - apiKey: The API key for authentication.
    /// - Returns: The structured fetch result.
    /// - Throws: ``OpenAIServiceError`` if fetching fails on all routes.
    func fetchResponse(responseId: String, apiKey: String) async throws(OpenAIServiceError) -> OpenAIResponseFetchResult {
        do {
            return try await fetchResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: false
            )
        } catch {
            guard requestBuilder.configuration.usesGatewayRouting else {
                throw error
            }

            return try await fetchResponse(
                responseId: responseId,
                apiKey: apiKey,
                useDirectBaseURL: true
            )
        }
    }

    /// Validates an API key by attempting to list models.
    /// - Parameter apiKey: The API key to validate.
    /// - Returns: `true` if the key is valid (returns HTTP 200).
    func validateAPIKey(_ apiKey: String) async -> Bool {
        let request: URLRequest
        do {
            request = try requestBuilder.modelsRequest(
                apiKey: apiKey,
                useDirectBaseURL: true
            )
        } catch {
            return false
        }

        do {
            let (_, response) = try await transport.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Returns a URL request for listing models, or `nil` if construction fails.
    /// - Parameter apiKey: The API key for authentication.
    /// - Returns: A configured URL request, or `nil`.
    func modelsRequest(apiKey: String) -> URLRequest? {
        do {
            return try requestBuilder.modelsRequest(
                apiKey: apiKey,
                useDirectBaseURL: true
            )
        } catch {
            return nil
        }
    }

    private func cancelResponse(
        responseId: String,
        apiKey: String,
        useDirectBaseURL: Bool
    ) async throws(OpenAIServiceError) {
        let request = try requestBuilder.cancelRequest(
            responseId: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )

        let (data, response) = try await transport.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Failed to cancel response"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }
    }

    private func fetchResponse(
        responseId: String,
        apiKey: String,
        useDirectBaseURL: Bool
    ) async throws(OpenAIServiceError) -> OpenAIResponseFetchResult {
        let request = try requestBuilder.fetchRequest(
            responseId: responseId,
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )

        let (data, response) = try await transport.data(for: request)
        return try responseParser.parseFetchedResponse(data: data, response: response)
    }
}
