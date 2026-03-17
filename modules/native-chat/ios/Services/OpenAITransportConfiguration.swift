import Foundation

protocol OpenAIConfigurationProvider: Sendable {
    var directOpenAIBaseURL: String { get }
    var openAIBaseURL: String { get }
    var cloudflareGatewayBaseURL: String { get }
    var cloudflareAIGToken: String { get }
    var useCloudflareGateway: Bool { get set }
}

protocol OpenAIRequestAuthorizer: Sendable {
    func applyAuthorization(
        to request: inout URLRequest,
        apiKey: String,
        includeCloudflareAuthorization: Bool
    )
}

protocol OpenAIDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

@MainActor
protocol OpenAIStreamClient: AnyObject {
    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent>
    func cancel()
}

struct OpenAIStandardRequestAuthorizer: OpenAIRequestAuthorizer {
    private let configuration: OpenAIConfigurationProvider

    init(configuration: OpenAIConfigurationProvider) {
        self.configuration = configuration
    }

    func applyAuthorization(
        to request: inout URLRequest,
        apiKey: String,
        includeCloudflareAuthorization: Bool
    ) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard includeCloudflareAuthorization, configuration.useCloudflareGateway else {
            return
        }

        request.setValue(
            "Bearer \(configuration.cloudflareAIGToken)",
            forHTTPHeaderField: "cf-aig-authorization"
        )
    }
}

final class OpenAIURLSessionTransport: OpenAIDataTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

final class DefaultOpenAIConfigurationProvider: OpenAIConfigurationProvider, @unchecked Sendable {
    private static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    private static let bundledCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    private static let bundledCloudflareAIGToken = "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"

    private let settingsStore: SettingsStore

    static let shared = DefaultOpenAIConfigurationProvider()

    init(settingsStore: SettingsStore = .shared) {
        self.settingsStore = settingsStore
    }

    var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : directOpenAIBaseURL
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
