import Foundation
import OpenAITransport

typealias OpenAIConfigurationProvider = OpenAITransport.OpenAIConfigurationProvider
typealias OpenAIResolvedEndpoint = OpenAITransport.OpenAIResolvedEndpoint
typealias OpenAIRequestAuthorizer = OpenAITransport.OpenAIRequestAuthorizer
typealias OpenAIDataTransport = OpenAITransport.OpenAIDataTransport
typealias OpenAIStandardRequestAuthorizer = OpenAITransport.OpenAIStandardRequestAuthorizer
typealias OpenAIURLSessionTransport = OpenAITransport.OpenAIURLSessionTransport

@MainActor
protocol OpenAIStreamClient: AnyObject {
    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent>
    func cancel()
}

final class DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider {
    private static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    private static let bundledCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    private static let bundledCloudflareAIGToken = "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"

    private let settingsStore: SettingsStore

    nonisolated(unsafe) static let shared = DefaultOpenAIConfigurationProvider()

    init(settingsStore: SettingsStore = .shared) {
        self.settingsStore = settingsStore
    }

    var directOpenAIBaseURL: String {
        Self.defaultOpenAIBaseURL
    }

    var cloudflareGatewayBaseURL: String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareGatewayBaseURL") as? String,
           !infoValue.isEmpty {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_GATEWAY_BASE_URL"],
           !environmentValue.isEmpty {
            return environmentValue
        }

        return Self.bundledCloudflareGatewayBaseURL
    }

    var cloudflareAIGToken: String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareAIGToken") as? String,
           !infoValue.isEmpty {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_AIG_TOKEN"],
           !environmentValue.isEmpty {
            return environmentValue
        }

        return Self.bundledCloudflareAIGToken
    }

    var useCloudflareGateway: Bool {
        get {
            settingsStore.cloudflareGatewayEnabled
        }
        set {
            settingsStore.cloudflareGatewayEnabled = newValue
        }
    }
}
