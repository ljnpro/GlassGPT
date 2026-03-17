import ChatDomain
import Foundation

public protocol OpenAIConfigurationProvider {
    var directOpenAIBaseURL: String { get }
    var cloudflareGatewayBaseURL: String { get }
    var cloudflareAIGToken: String { get }
    var useCloudflareGateway: Bool { get set }
}

public struct OpenAIResolvedEndpoint: Sendable {
    public let route: OpenAITransportRoute
    public let baseURL: String
    public let includeCloudflareAuthorization: Bool

    public init(
        route: OpenAITransportRoute,
        baseURL: String,
        includeCloudflareAuthorization: Bool
    ) {
        self.route = route
        self.baseURL = baseURL
        self.includeCloudflareAuthorization = includeCloudflareAuthorization
    }

    public var usesGatewayRouting: Bool {
        route == .gateway
    }
}

public extension OpenAIConfigurationProvider {
    var openAIBaseURL: String {
        resolvedEndpoint().baseURL
    }

    var resolvedRoute: OpenAITransportRoute {
        useCloudflareGateway ? .gateway : .direct
    }

    var usesGatewayRouting: Bool {
        resolvedRoute == .gateway
    }

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
