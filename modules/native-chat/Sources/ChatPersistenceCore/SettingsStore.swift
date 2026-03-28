import Foundation

/// Reads and writes user-facing settings, backed by a ``SettingsValueStore``.
public final class SettingsStore {
    /// `UserDefaults` keys for all persisted settings.
    public enum Keys {
        public static let defaultModel = "defaultModel"
        public static let defaultEffort = "defaultEffort"
        public static let defaultServiceTier = "defaultServiceTier"
        public static let defaultAgentLeaderEffort = "defaultAgentLeaderEffort"
        public static let defaultAgentWorkerEffort = "defaultAgentWorkerEffort"
        public static let defaultAgentServiceTier = "defaultAgentServiceTier"
        public static let appTheme = "appTheme"
        public static let hapticEnabled = "hapticEnabled"
    }

    let valueStore: any SettingsValueStore

    /// Creates a settings store backed by the given value store.
    public init(valueStore: any SettingsValueStore = UserDefaultsSettingsValueStore(defaults: .standard)) {
        self.valueStore = valueStore
    }
}
