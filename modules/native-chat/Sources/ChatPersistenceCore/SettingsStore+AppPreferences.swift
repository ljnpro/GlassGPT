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
}
