import Foundation
import os.lock

/// Thread-safe configuration provider for OpenAI API endpoints with optional Cloudflare gateway routing.
public final class DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider, Sendable {
    /// The default direct OpenAI API base URL.
    public static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    /// The default Cloudflare AI Gateway base URL.
    public static let defaultCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    /// The default bundled Cloudflare AI Gateway authorization token.
    public static let defaultCloudflareAIGToken =
        "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"

    private struct State {
        var cloudflareGatewayBaseURL: String
        var cloudflareAIGToken: String
        var useCloudflareGateway: Bool
    }

    /// The base URL for direct OpenAI API requests.
    public let directOpenAIBaseURL: String
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
        cloudflareAIGToken: String = DefaultOpenAIConfigurationProvider.defaultCloudflareAIGToken,
        useCloudflareGateway: Bool = false
    ) {
        self.directOpenAIBaseURL = directOpenAIBaseURL
        state = OSAllocatedUnfairLock(
            initialState: State(
                cloudflareGatewayBaseURL: cloudflareGatewayBaseURL,
                cloudflareAIGToken: cloudflareAIGToken,
                useCloudflareGateway: useCloudflareGateway
            )
        )
    }

    /// The base URL for Cloudflare AI Gateway proxy requests. Thread-safe.
    public var cloudflareGatewayBaseURL: String {
        get { state.withLock { $0.cloudflareGatewayBaseURL } }
        set {
            state.withLock { $0.cloudflareGatewayBaseURL = newValue }
        }
    }

    /// The Cloudflare AI Gateway authorization token. Thread-safe.
    public var cloudflareAIGToken: String {
        get { state.withLock { $0.cloudflareAIGToken } }
        set {
            state.withLock { $0.cloudflareAIGToken = newValue }
        }
    }

    /// Whether to route API requests through the Cloudflare AI Gateway. Thread-safe.
    public var useCloudflareGateway: Bool {
        get { state.withLock { $0.useCloudflareGateway } }
        set {
            state.withLock { $0.useCloudflareGateway = newValue }
        }
    }
}
