import Foundation

enum FeatureFlags {
    private static let cloudflareEnabledKey = "cloudflareGatewayEnabled"
    private static let defaultOpenAIBaseURL = "https://api.openai.com/v1"

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

    static let cloudflareGatewayBaseURL =
        "https://gateway.ai.cloudflare.com/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai"
    static let cloudflareAIGToken = "W3AAxNEfdJNnhh-tT-w9TX4mPTLtU2_e_ox0Pwd7"

    static var useCloudflareGateway: Bool {
        get { UserDefaults.standard.bool(forKey: cloudflareEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: cloudflareEnabledKey)
            if !newValue {
                platformRelayStorage.store(nil)
            }
        }
    }

    static var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : defaultOpenAIBaseURL
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
