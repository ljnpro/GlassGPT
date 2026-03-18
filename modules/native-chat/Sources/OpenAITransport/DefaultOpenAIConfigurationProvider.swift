import Foundation
import os.lock

public final class DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider, Sendable {
    public static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    public static let defaultCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"

    private struct State {
        var useCloudflareGateway: Bool
    }

    public let directOpenAIBaseURL: String
    public let cloudflareGatewayBaseURL: String
    public let cloudflareAIGToken: String
    private let state: OSAllocatedUnfairLock<State>

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

    public var useCloudflareGateway: Bool {
        get { state.withLock { $0.useCloudflareGateway } }
        set {
            state.withLock { $0.useCloudflareGateway = newValue }
        }
    }
}
