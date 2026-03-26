import ChatDomain
import Foundation

public extension SettingsStore {
    /// The selected appearance theme. Falls back to `.system` if unset.
    var appTheme: AppTheme {
        get {
            guard let raw = valueStore.string(forKey: Keys.appTheme),
                  let theme = AppTheme(rawValue: raw)
            else {
                return .system
            }
            return theme
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.appTheme)
        }
    }

    /// Whether haptic feedback is enabled. Defaults to `true` if unset.
    var hapticEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.hapticEnabled) as? Bool ?? true
        }
        set {
            valueStore.set(newValue, forKey: Keys.hapticEnabled)
        }
    }

    /// Whether the Cloudflare AI gateway is enabled. Defaults to `false` if unset.
    var cloudflareGatewayEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.cloudflareGatewayEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.cloudflareGatewayEnabled)
        }
    }

    /// The persisted Cloudflare gateway configuration mode. Defaults to `.default` if unset.
    var cloudflareGatewayConfigurationMode: CloudflareGatewayConfigurationMode {
        get {
            guard let rawValue = valueStore.string(forKey: Keys.cloudflareGatewayConfigurationMode),
                  let mode = CloudflareGatewayConfigurationMode(rawValue: rawValue)
            else {
                return .default
            }
            return mode
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.cloudflareGatewayConfigurationMode)
        }
    }

    /// The persisted custom Cloudflare gateway base URL. Defaults to an empty string if unset.
    var customCloudflareGatewayBaseURL: String {
        get {
            valueStore.string(forKey: Keys.customCloudflareGatewayBaseURL) ?? ""
        }
        set {
            valueStore.set(newValue, forKey: Keys.customCloudflareGatewayBaseURL)
        }
    }
}
