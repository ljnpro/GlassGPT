import Foundation

public struct OpenAIRequestDescriptor: Sendable {
    public let path: String
    public let method: String
    public let accept: String
    public let timeoutInterval: TimeInterval
    public let queryItems: [URLQueryItem]
    public let includeCloudflareAuthorization: Bool?
    public let contentType: String?

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

public struct OpenAIRequestFactory {
    let configuration: any OpenAIConfigurationProvider
    let requestAuthorizer: any OpenAIRequestAuthorizer

    public init(
        configuration: any OpenAIConfigurationProvider,
        requestAuthorizer: (any OpenAIRequestAuthorizer)? = nil
    ) {
        self.configuration = configuration
        self.requestAuthorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(
            configuration: configuration
        )
    }

    public func responsesURL(useDirectBaseURL: Bool = false) throws -> URL {
        try url(
            for: OpenAIRequestDescriptor(path: "/responses", method: "GET"),
            useDirectBaseURL: useDirectBaseURL
        )
    }

    public func responseURL(
        responseID: String,
        stream: Bool,
        startingAfter: Int? = nil,
        include: [String]? = nil,
        useDirectBaseURL: Bool = false
    ) throws -> URL {
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

    public func request(
        for descriptor: OpenAIRequestDescriptor,
        apiKey: String,
        body: Data? = nil,
        useDirectBaseURL: Bool = false
    ) throws -> URLRequest {
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

    public func url(
        for descriptor: OpenAIRequestDescriptor,
        useDirectBaseURL: Bool = false
    ) throws -> URL {
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
