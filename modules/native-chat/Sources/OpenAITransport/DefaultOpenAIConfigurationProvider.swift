import Foundation
import os.lock

/// Thread-safe configuration provider for OpenAI API endpoints with optional Cloudflare gateway routing.
public final class DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider, Sendable {
    /// The default direct OpenAI API base URL.
    public static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    /// The default Cloudflare AI Gateway base URL.
    public static let defaultCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"

    private struct State {
        var useCloudflareGateway: Bool
    }

    /// The base URL for direct OpenAI API requests.
    public let directOpenAIBaseURL: String
    /// The base URL for Cloudflare AI Gateway proxy requests.
    public let cloudflareGatewayBaseURL: String
    /// The Cloudflare AI Gateway authorization token.
    public let cloudflareAIGToken: String
    private let state: OSAllocatedUnfairLock<State>

    /// Creates a new configuration provider.
    /// - Parameters:
    ///   - directOpenAIBaseURL: The direct API base URL.
    ///   - cloudflareGatewayBaseURL: The Cloudflare gateway base URL.
    ///   - cloudflareAIGToken: The Cloudflare AI Gateway authorization token.
    ///   - useCloudflareGateway: Whether to route requests through the Cloudflare gateway.
    public init(
        directOpenAIBaseURL: String = DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL,
        cloudflareGatewayBaseURL: String = DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL,
        cloudflareAIGToken: String = "",
        useCloudflareGateway: Bool = false
    ) {
        self.directOpenAIBaseURL = directOpenAIBaseURL
        self.cloudflareGatewayBaseURL = cloudflareGatewayBaseURL
        self.cloudflareAIGToken = cloudflareAIGToken
        self.state = OSAllocatedUnfairLock(
            initialState: State(
                useCloudflareGateway: useCloudflareGateway
            )
        )
    }

    /// Whether to route API requests through the Cloudflare AI Gateway. Thread-safe.
    public var useCloudflareGateway: Bool {
        get { state.withLock { $0.useCloudflareGateway } }
        set {
            state.withLock { $0.useCloudflareGateway = newValue }
        }
    }
}
