import Foundation

enum FeatureFlags {
    private static let relayEnabledKey = "relayServerEnabled"
    private static let relayURLKey = "relayServerURL"

    // MARK: - Thread-safe storage for platform relay URL

    private final class PlatformRelayStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var _url: String?

        var url: String? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _url
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _url = newValue
            }
        }
    }

    private static let platformRelayStorage = PlatformRelayStorage()

    private static var storedRelayURL: String? {
        let stored = UserDefaults.standard.string(forKey: relayURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? nil : stored
    }

    static var platformRelayURL: String? {
        get {
            platformRelayStorage.url
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolved = trimmed.isEmpty ? nil : trimmed
            platformRelayStorage.url = resolved

            if resolved != nil {
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
            if let stored = storedRelayURL {
                return stored
            }

            if let platform = platformRelayStorage.url, !platform.isEmpty {
                return platform
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
        storedRelayURL == nil && (platformRelayStorage.url?.isEmpty == false)
    }

    static var isRelayConfigured: Bool {
        useRelayServer && !relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func configurePlatformRelay(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? nil : trimmed
        platformRelayStorage.url = resolved
        if resolved != nil {
            useRelayServer = true
        }
    }
}
