import Foundation

/// Reads and writes user-facing settings, backed by a ``SettingsValueStore``.
public final class SettingsStore {
    /// `UserDefaults` keys for all persisted settings.
    public enum Keys {
        public static let defaultModel = "defaultModel"
        public static let defaultEffort = "defaultEffort"
        public static let defaultBackgroundModeEnabled = "defaultBackgroundModeEnabled"
        public static let defaultServiceTier = "defaultServiceTier"
        public static let defaultAgentLeaderEffort = "defaultAgentLeaderEffort"
        public static let defaultAgentWorkerEffort = "defaultAgentWorkerEffort"
        public static let defaultAgentBackgroundModeEnabled = "defaultAgentBackgroundModeEnabled"
        public static let defaultAgentServiceTier = "defaultAgentServiceTier"
        public static let appTheme = "appTheme"
        public static let hapticEnabled = "hapticEnabled"
        public static let cloudflareGatewayEnabled = "cloudflareGatewayEnabled"
        public static let cloudflareGatewayConfigurationMode = "cloudflareGatewayConfigurationMode"
        public static let customCloudflareGatewayBaseURL = "customCloudflareGatewayBaseURL"
    }

    let valueStore: any SettingsValueStore

    /// Creates a settings store backed by the given value store.
    public init(valueStore: any SettingsValueStore = UserDefaultsSettingsValueStore(defaults: .standard)) {
        self.valueStore = valueStore
    }
}
