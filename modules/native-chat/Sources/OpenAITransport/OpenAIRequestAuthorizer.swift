import Foundation

/// Abstraction for applying authorization headers to API requests.
public protocol OpenAIRequestAuthorizer: Sendable {
    /// Applies authorization headers to the given request.
    /// - Parameters:
    ///   - request: The request to authorize.
    ///   - apiKey: The OpenAI API key.
    ///   - includeCloudflareAuthorization: Whether to include Cloudflare gateway authorization.
    func applyAuthorization(
        to request: inout URLRequest,
        apiKey: String,
        includeCloudflareAuthorization: Bool
    )
}

/// Standard authorizer that sets Bearer tokens for OpenAI and optionally Cloudflare gateway.
public struct OpenAIStandardRequestAuthorizer: OpenAIRequestAuthorizer {
    private let configuration: OpenAIConfigurationProvider

    /// Creates a new standard request authorizer.
    /// - Parameter configuration: The configuration providing Cloudflare credentials.
    public init(configuration: OpenAIConfigurationProvider) {
        self.configuration = configuration
    }

    /// Applies OpenAI Bearer authorization and optionally Cloudflare AI Gateway authorization.
    /// - Parameters:
    ///   - request: The request to authorize.
    ///   - apiKey: The OpenAI API key.
    ///   - includeCloudflareAuthorization: Whether to include Cloudflare gateway authorization.
    public func applyAuthorization(
        to request: inout URLRequest,
        apiKey: String,
        includeCloudflareAuthorization: Bool
    ) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard includeCloudflareAuthorization, configuration.usesGatewayRouting else {
            return
        }

        let aigToken = configuration.cloudflareAIGToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aigToken.isEmpty else { return }

        request.setValue("Bearer \(aigToken)", forHTTPHeaderField: "cf-aig-authorization")
    }
}
