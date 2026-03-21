import Foundation

public extension OpenAIRequestFactory {
    /// The default set of include parameters for fetching response details.
    static let defaultFetchIncludes = ["code_interpreter_call.outputs", "file_search_call.results", "web_search_call.action.sources"]

    /// Builds a request for listing available models.
    /// - Parameters:
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func modelsRequest(
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try request(
            for: OpenAIRequestDescriptor(
                path: "/models",
                method: "GET",
                timeoutInterval: 10
            ),
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for cancelling an in-progress response.
    /// - Parameters:
    ///   - responseID: The API response identifier to cancel.
    ///   - apiKey: The API key for authentication.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func cancelRequest(
        responseID: String,
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try request(
            for: OpenAIRequestDescriptor(
                pathSegments: ["responses", responseID, "cancel"],
                method: "POST",
                timeoutInterval: 30
            ),
            apiKey: apiKey,
            body: Data(),
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for fetching a completed response.
    /// - Parameters:
    ///   - responseID: The API response identifier to fetch.
    ///   - apiKey: The API key for authentication.
    ///   - include: Response detail includes. Defaults to ``defaultFetchIncludes``.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func fetchRequest(
        responseID: String,
        apiKey: String,
        include: [String] = defaultFetchIncludes,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        try request(
            for: OpenAIRequestDescriptor(
                pathSegments: ["responses", responseID],
                method: "GET",
                timeoutInterval: 30,
                queryItems: include.map { URLQueryItem(name: "include[]", value: $0) }
            ),
            apiKey: apiKey,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}
