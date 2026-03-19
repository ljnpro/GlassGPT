import ChatDomain
import Foundation

/// Provides the configuration needed to resolve API endpoints and authorization.
public protocol OpenAIConfigurationProvider: Sendable {
    /// The base URL for direct OpenAI API requests.
    var directOpenAIBaseURL: String { get }
    /// The base URL for Cloudflare AI Gateway proxy requests.
    var cloudflareGatewayBaseURL: String { get }
    /// The Cloudflare AI Gateway authorization token.
    var cloudflareAIGToken: String { get }
    /// Whether to route API requests through the Cloudflare gateway.
    var useCloudflareGateway: Bool { get set }
}

/// A fully resolved API endpoint with its route, base URL, and authorization requirements.
public struct OpenAIResolvedEndpoint: Sendable {
    /// The transport route for this endpoint.
    public let route: OpenAITransportRoute
    /// The base URL string for this endpoint.
    public let baseURL: String
    /// Whether requests to this endpoint require Cloudflare authorization.
    public let includeCloudflareAuthorization: Bool

    /// Creates a new resolved endpoint.
    /// - Parameters:
    ///   - route: The transport route.
    ///   - baseURL: The base URL string.
    ///   - includeCloudflareAuthorization: Whether Cloudflare authorization is required.
    public init(
        route: OpenAITransportRoute,
        baseURL: String,
        includeCloudflareAuthorization: Bool
    ) {
        self.route = route
        self.baseURL = baseURL
        self.includeCloudflareAuthorization = includeCloudflareAuthorization
    }

    /// Whether this endpoint uses the Cloudflare gateway route.
    public var usesGatewayRouting: Bool {
        route == .gateway
    }
}

public extension OpenAIConfigurationProvider {
    /// The resolved base URL for the current routing configuration.
    var openAIBaseURL: String {
        resolvedEndpoint().baseURL
    }

    /// The transport route derived from the gateway configuration.
    var resolvedRoute: OpenAITransportRoute {
        useCloudflareGateway ? .gateway : .direct
    }

    /// Whether the current configuration routes through the Cloudflare gateway.
    var usesGatewayRouting: Bool {
        resolvedRoute == .gateway
    }

    /// Resolves the full endpoint configuration for the current routing settings.
    /// - Parameter useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A fully resolved endpoint.
    func resolvedEndpoint(useDirectBaseURL: Bool = false) -> OpenAIResolvedEndpoint {
        let route: OpenAITransportRoute = useDirectBaseURL ? .direct : resolvedRoute
        let baseURL = route == .gateway ? cloudflareGatewayBaseURL : directOpenAIBaseURL
        return OpenAIResolvedEndpoint(
            route: route,
            baseURL: baseURL,
            includeCloudflareAuthorization: route.includesCloudflareAuthorization
        )
    }
}
