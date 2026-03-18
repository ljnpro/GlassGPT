import Foundation
import os.lock

public final class DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider, Sendable {
    public static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    public static let bundledCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    public static let bundledCloudflareAIGToken = "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"

    public static let shared = DefaultOpenAIConfigurationProvider()

    private struct State {
        var directBaseURLProvider: @Sendable () -> String
        var gatewayBaseURLProvider: @Sendable () -> String
        var aigTokenProvider: @Sendable () -> String
        var useGatewayProvider: @Sendable () -> Bool
        var setUseGatewayProvider: @Sendable (Bool) -> Void
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(
        directOpenAIBaseURL: @escaping @Sendable () -> String = { DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL },
        cloudflareGatewayBaseURL: @escaping @Sendable () -> String = { DefaultOpenAIConfigurationProvider.bundledCloudflareGatewayBaseURL },
        cloudflareAIGToken: @escaping @Sendable () -> String = { DefaultOpenAIConfigurationProvider.bundledCloudflareAIGToken },
        useCloudflareGateway: @escaping @Sendable () -> Bool = { false },
        setUseCloudflareGateway: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(
                directBaseURLProvider: directOpenAIBaseURL,
                gatewayBaseURLProvider: cloudflareGatewayBaseURL,
                aigTokenProvider: cloudflareAIGToken,
                useGatewayProvider: useCloudflareGateway,
                setUseGatewayProvider: setUseCloudflareGateway
            )
        )
    }

    public func configure(
        directOpenAIBaseURL: @escaping @Sendable () -> String,
        cloudflareGatewayBaseURL: @escaping @Sendable () -> String,
        cloudflareAIGToken: @escaping @Sendable () -> String,
        useCloudflareGateway: @escaping @Sendable () -> Bool,
        setUseCloudflareGateway: @escaping @Sendable (Bool) -> Void
    ) {
        state.withLock { state in
            state.directBaseURLProvider = directOpenAIBaseURL
            state.gatewayBaseURLProvider = cloudflareGatewayBaseURL
            state.aigTokenProvider = cloudflareAIGToken
            state.useGatewayProvider = useCloudflareGateway
            state.setUseGatewayProvider = setUseCloudflareGateway
        }
    }

    public var directOpenAIBaseURL: String {
        state.withLock { $0.directBaseURLProvider() }
    }

    public var cloudflareGatewayBaseURL: String {
        state.withLock { $0.gatewayBaseURLProvider() }
    }

    public var cloudflareAIGToken: String {
        state.withLock { $0.aigTokenProvider() }
    }

    public var useCloudflareGateway: Bool {
        get { state.withLock { $0.useGatewayProvider() } }
        set {
            let setter = state.withLock { $0.setUseGatewayProvider }
            setter(newValue)
        }
    }
}
