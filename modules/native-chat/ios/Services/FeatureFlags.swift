import Foundation

enum FeatureFlags {
    private static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    private static let bundledCloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    private static let bundledCloudflareAIGToken = "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"

    // Legacy storage kept to preserve the prior concurrency-safe relay config shape.
    private final class PlatformRelayStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var url: String?

        func store(_ newValue: String?) {
            lock.lock()
            defer { lock.unlock() }
            url = newValue
        }
    }

    private static let platformRelayStorage = PlatformRelayStorage()

    static var cloudflareGatewayBaseURL: String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareGatewayBaseURL") as? String,
           !infoValue.isEmpty {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_GATEWAY_BASE_URL"],
           !environmentValue.isEmpty {
            return environmentValue
        }

        return bundledCloudflareGatewayBaseURL
    }

    static var cloudflareAIGToken: String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareAIGToken") as? String,
           !infoValue.isEmpty {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_AIG_TOKEN"],
           !environmentValue.isEmpty {
            return environmentValue
        }

        return bundledCloudflareAIGToken
    }

    static var useCloudflareGateway: Bool {
        get { SettingsStore.shared.cloudflareGatewayEnabled }
        set {
            SettingsStore.shared.cloudflareGatewayEnabled = newValue
            if !newValue {
                platformRelayStorage.store(nil)
            }
        }
    }

    static var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : defaultOpenAIBaseURL
    }

    static var directOpenAIBaseURL: String {
        defaultOpenAIBaseURL
    }

    static var isCloudflareConfigured: Bool {
        useCloudflareGateway
    }

    static func applyCloudflareAuthorization(to request: inout URLRequest) {
        guard useCloudflareGateway else { return }
        request.setValue(
            "Bearer \(cloudflareAIGToken)",
            forHTTPHeaderField: "cf-aig-authorization"
        )
    }
}
