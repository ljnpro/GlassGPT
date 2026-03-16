import Foundation

protocol SettingsValueStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Any?, forKey defaultName: String)
}

final class UserDefaultsSettingsValueStore: SettingsValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func object(forKey defaultName: String) -> Any? {
        defaults.object(forKey: defaultName)
    }

    func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    func bool(forKey defaultName: String) -> Bool {
        defaults.bool(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }
}

final class SettingsStore: @unchecked Sendable {
    enum Keys {
        static let defaultModel = "defaultModel"
        static let defaultEffort = "defaultEffort"
        static let defaultBackgroundModeEnabled = "defaultBackgroundModeEnabled"
        static let defaultServiceTier = "defaultServiceTier"
        static let appTheme = "appTheme"
        static let hapticEnabled = "hapticEnabled"
        static let cloudflareGatewayEnabled = "cloudflareGatewayEnabled"
    }

    static let shared = SettingsStore()

    private let valueStore: SettingsValueStore

    init(valueStore: SettingsValueStore = UserDefaultsSettingsValueStore(defaults: .standard)) {
        self.valueStore = valueStore
    }

    var defaultModel: ModelType {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultModel),
                  let model = ModelType(rawValue: raw)
            else {
                return .gpt5_4_pro
            }
            return model
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultModel)
        }
    }

    var defaultEffort: ReasoningEffort {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultEffort),
                  let effort = ReasoningEffort(rawValue: raw)
            else {
                return .xhigh
            }

            let resolvedModel = defaultModel
            return resolvedModel.availableEfforts.contains(effort) ? effort : resolvedModel.defaultEffort
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultEffort)
        }
    }

    var defaultBackgroundModeEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.defaultBackgroundModeEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.defaultBackgroundModeEnabled)
        }
    }

    var defaultServiceTier: ServiceTier {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultServiceTier),
                  let tier = ServiceTier(rawValue: raw)
            else {
                return .standard
            }
            return tier
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultServiceTier)
        }
    }

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

    var hapticEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.hapticEnabled) as? Bool ?? true
        }
        set {
            valueStore.set(newValue, forKey: Keys.hapticEnabled)
        }
    }

    var cloudflareGatewayEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.cloudflareGatewayEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.cloudflareGatewayEnabled)
        }
    }

    var defaultConversationConfiguration: ConversationConfiguration {
        let model = defaultModel
        let resolvedEffort = model.availableEfforts.contains(defaultEffort) ? defaultEffort : model.defaultEffort
        return ConversationConfiguration(
            model: model,
            reasoningEffort: resolvedEffort,
            backgroundModeEnabled: defaultBackgroundModeEnabled,
            serviceTier: defaultServiceTier
        )
    }
}
