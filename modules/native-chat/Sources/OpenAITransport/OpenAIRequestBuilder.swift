import Foundation

private struct StaticOpenAIConfigurationProvider: OpenAIConfigurationProvider {
    let directOpenAIBaseURL = "https://api.openai.com/v1"
    let cloudflareGatewayBaseURL: String = DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL
    let cloudflareAIGToken = ""
    var useCloudflareGateway = false
}

/// High-level builder that composes configuration, authorization, and request factory
/// to produce ready-to-send ``URLRequest`` instances for the OpenAI API.
public struct OpenAIRequestBuilder {
    /// The configuration provider for endpoint resolution.
    public let configuration: OpenAIConfigurationProvider
    /// The authorizer for applying authentication headers.
    public let requestAuthorizer: OpenAIRequestAuthorizer
    /// The underlying factory used to construct requests.
    public let requestFactory: OpenAIRequestFactory

    /// Creates a new request builder.
    /// - Parameters:
    ///   - configuration: The configuration provider. Required.
    ///   - requestAuthorizer: An optional custom authorizer. Defaults to ``OpenAIStandardRequestAuthorizer``.
    public init(
        configuration: OpenAIConfigurationProvider,
        requestAuthorizer: OpenAIRequestAuthorizer? = nil
    ) {
        let resolvedAuthorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(
            configuration: configuration
        )
        self.configuration = configuration
        self.requestAuthorizer = resolvedAuthorizer
        requestFactory = OpenAIRequestFactory(
            configuration: configuration,
            requestAuthorizer: resolvedAuthorizer
        )
    }

    /// Creates a request builder with default static configuration.
    public init() {
        self.init(configuration: StaticOpenAIConfigurationProvider())
    }

    /// Returns the responses endpoint URL as a string.
    /// - Parameter useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: The absolute URL string for the responses endpoint.
    public func responsesURL(useDirectBaseURL: Bool = false) -> String {
        do {
            let url = try requestFactory.responsesURL(useDirectBaseURL: useDirectBaseURL)
            return url.absoluteString
        } catch {
            return "\(configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL).baseURL)/responses"
        }
    }
}
