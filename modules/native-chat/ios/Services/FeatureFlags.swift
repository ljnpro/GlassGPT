import Foundation

enum FeatureFlags {
    private static let relayEnabledKey = "relayServerEnabled"
    private static let relayURLKey = "relayServerURL"

    static var useRelayServer: Bool {
        get {
            UserDefaults.standard.bool(forKey: relayEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: relayEnabledKey)
        }
    }

    static var relayServerURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: relayURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stored.isEmpty {
                return stored
            }

            let env = ProcessInfo.processInfo.environment
            let envURL =
                env["LIQUID_GLASS_CHAT_RELAY_SERVER_URL"] ??
                env["RELAY_SERVER_URL"] ??
                env["LIQUID_GLASS_RELAY_SERVER_URL"] ??
                ""

            return envURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: relayURLKey)
        }
    }

    static var isRelayConfigured: Bool {
        useRelayServer && !relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
