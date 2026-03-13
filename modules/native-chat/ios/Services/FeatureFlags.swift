import Foundation

enum FeatureFlags {
    private static let relayEnabledKey = "relayServerEnabled"
    private static let relayURLKey = "relayServerURL"

    private static var _platformRelayURL: String?

    private static var storedRelayURL: String? {
        let stored = UserDefaults.standard.string(forKey: relayURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? nil : stored
    }

    static var platformRelayURL: String? {
        get {
            _platformRelayURL
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            _platformRelayURL = trimmed.isEmpty ? nil : trimmed

            if _platformRelayURL != nil {
                useRelayServer = true
            }
        }
    }

    static var useRelayServer: Bool {
        get {
            if let stored = UserDefaults.standard.object(forKey: relayEnabledKey) as? Bool {
                return stored
            }

            return !relayServerURL.isEmpty
        }
        set {
            UserDefaults.standard.set(newValue, forKey: relayEnabledKey)
        }
    }

    static var relayServerURL: String {
        get {
            if let storedRelayURL {
                return storedRelayURL
            }

            if let platformRelayURL, !platformRelayURL.isEmpty {
                return platformRelayURL
            }

            return ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: relayURLKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: relayURLKey)
                useRelayServer = true
            }
        }
    }

    static var isRelayAutoDetected: Bool {
        storedRelayURL == nil && (platformRelayURL?.isEmpty == false)
    }

    static var isRelayConfigured: Bool {
        useRelayServer && !relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func configurePlatformRelay(url: String) {
        platformRelayURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if platformRelayURL != nil {
            useRelayServer = true
        }
    }
}
