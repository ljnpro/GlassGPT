import Foundation

/// Describes the parameters needed to construct an API request.
public struct OpenAIRequestDescriptor: Sendable {
    /// The API path relative to the base URL (e.g. "/responses").
    public let path: String
    /// The HTTP method (e.g. "GET", "POST").
    public let method: String
    /// The Accept header value.
    public let accept: String
    /// The request timeout interval in seconds.
    public let timeoutInterval: TimeInterval
    /// URL query items to append to the request.
    public let queryItems: [URLQueryItem]
    /// Override for whether to include Cloudflare authorization, or `nil` for auto.
    public let includeCloudflareAuthorization: Bool?
    /// Override for the Content-Type header, or `nil` for auto.
    public let contentType: String?

    /// Creates a new request descriptor.
    public init(
        path: String,
        method: String,
        accept: String = "application/json",
        timeoutInterval: TimeInterval = 60,
        queryItems: [URLQueryItem] = [],
        includeCloudflareAuthorization: Bool? = nil,
        contentType: String? = nil
    ) {
        self.path = path
        self.method = method
        self.accept = accept
        self.timeoutInterval = timeoutInterval
        self.queryItems = queryItems
        self.includeCloudflareAuthorization = includeCloudflareAuthorization
        self.contentType = contentType
    }
}

/// Low-level factory for constructing authorized ``URLRequest`` instances for the OpenAI API.
public struct OpenAIRequestFactory {
    /// The configuration provider for endpoint resolution.
    let configuration: any OpenAIConfigurationProvider
    /// The authorizer for applying authentication headers.
    let requestAuthorizer: any OpenAIRequestAuthorizer

    /// Creates a new request factory.
    /// - Parameters:
    ///   - configuration: The configuration provider.
    ///   - requestAuthorizer: An optional custom authorizer. Defaults to ``OpenAIStandardRequestAuthorizer``.
    public init(
        configuration: any OpenAIConfigurationProvider,
        requestAuthorizer: (any OpenAIRequestAuthorizer)? = nil
    ) {
        self.configuration = configuration
        self.requestAuthorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(
            configuration: configuration
        )
    }

    /// Returns the URL for the responses endpoint.
    /// - Parameter useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: The responses endpoint URL.
    /// - Throws: ``OpenAIServiceError/invalidURL`` if the URL cannot be constructed.
    public func responsesURL(useDirectBaseURL: Bool = false) throws(OpenAIServiceError) -> URL {
        try url(
            for: OpenAIRequestDescriptor(path: "/responses", method: "GET"),
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Returns the URL for a specific response, with optional streaming and pagination parameters.
    /// - Parameters:
    ///   - responseID: The API response identifier.
    ///   - stream: Whether to request streaming output.
    ///   - startingAfter: The sequence number to resume after, if any.
    ///   - include: Additional include parameters for the response.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: The response URL.
    /// - Throws: ``OpenAIServiceError/invalidURL`` if the URL cannot be constructed.
    public func responseURL(
        responseID: String,
        stream: Bool,
        startingAfter: Int? = nil,
        include: [String]? = nil,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URL {
        var queryItems: [URLQueryItem] = []

        if stream {
            queryItems.append(URLQueryItem(name: "stream", value: "true"))
        }

        if let startingAfter {
            queryItems.append(URLQueryItem(name: "starting_after", value: String(startingAfter)))
        }

        if let include {
            queryItems.append(contentsOf: include.map { URLQueryItem(name: "include[]", value: $0) })
        }

        return try url(
            for: OpenAIRequestDescriptor(
                path: "/responses/\(responseID)",
                method: "GET",
                queryItems: queryItems
            ),
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a fully authorized ``URLRequest`` from a descriptor.
    /// - Parameters:
    ///   - descriptor: The request descriptor specifying path, method, and headers.
    ///   - apiKey: The API key for authentication.
    ///   - body: Optional HTTP body data.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured and authorized URL request.
    /// - Throws: ``OpenAIServiceError/invalidURL`` if the URL cannot be constructed.
    public func request(
        for descriptor: OpenAIRequestDescriptor,
        apiKey: String,
        body: Data? = nil,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        let endpoint = configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)
        let url = try url(for: descriptor, useDirectBaseURL: useDirectBaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = descriptor.method
        request.timeoutInterval = descriptor.timeoutInterval
        request.setValue(descriptor.accept, forHTTPHeaderField: "Accept")

        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: descriptor.includeCloudflareAuthorization
                ?? endpoint.includeCloudflareAuthorization
        )

        if let contentType = descriptor.contentType ?? defaultContentType(for: descriptor.method) {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        request.httpBody = body
        return request
    }

    /// Constructs the URL for a request descriptor.
    /// - Parameters:
    ///   - descriptor: The request descriptor.
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: The constructed URL.
    /// - Throws: ``OpenAIServiceError/invalidURL`` if the URL cannot be constructed.
    public func url(
        for descriptor: OpenAIRequestDescriptor,
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URL {
        let endpoint = configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)
        guard var components = URLComponents(string: endpoint.baseURL) else {
            throw OpenAIServiceError.invalidURL
        }

        let normalizedPath = normalizedPath(basePath: components.path, requestPath: descriptor.path)
        components.path = normalizedPath
        components.queryItems = descriptor.queryItems.isEmpty ? nil : descriptor.queryItems

        guard let url = components.url else {
            throw OpenAIServiceError.invalidURL
        }

        return url
    }

    private func defaultContentType(for method: String) -> String? {
        method.uppercased() == "GET" ? nil : "application/json"
    }

    private func normalizedPath(basePath: String, requestPath: String) -> String {
        let baseSegments = basePath.split(separator: "/").map(String.init)
        let requestSegments = requestPath.split(separator: "/").map(String.init)
        return "/" + (baseSegments + requestSegments).joined(separator: "/")
    }
}
