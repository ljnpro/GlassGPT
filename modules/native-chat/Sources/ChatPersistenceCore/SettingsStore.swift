import ChatDomain
import Foundation

public protocol SettingsValueStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Any?, forKey defaultName: String)
}

public final class UserDefaultsSettingsValueStore: SettingsValueStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func object(forKey defaultName: String) -> Any? {
        defaults.object(forKey: defaultName)
    }

    public func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    public func bool(forKey defaultName: String) -> Bool {
        defaults.bool(forKey: defaultName)
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }
}

public final class SettingsStore {
    public enum Keys {
        public static let defaultModel = "defaultModel"
        public static let defaultEffort = "defaultEffort"
        public static let defaultBackgroundModeEnabled = "defaultBackgroundModeEnabled"
        public static let defaultServiceTier = "defaultServiceTier"
        public static let appTheme = "appTheme"
        public static let hapticEnabled = "hapticEnabled"
        public static let cloudflareGatewayEnabled = "cloudflareGatewayEnabled"
    }

    private let valueStore: any SettingsValueStore

    public init(valueStore: any SettingsValueStore = UserDefaultsSettingsValueStore(defaults: .standard)) {
        self.valueStore = valueStore
    }

    public var defaultModel: ModelType {
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

    public var defaultEffort: ReasoningEffort {
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

    public var defaultBackgroundModeEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.defaultBackgroundModeEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.defaultBackgroundModeEnabled)
        }
    }

    public var defaultServiceTier: ServiceTier {
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

    public var appTheme: AppTheme {
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

    public var hapticEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.hapticEnabled) as? Bool ?? true
        }
        set {
            valueStore.set(newValue, forKey: Keys.hapticEnabled)
        }
    }

    public var cloudflareGatewayEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.cloudflareGatewayEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.cloudflareGatewayEnabled)
        }
    }

    public var defaultConversationConfiguration: ConversationConfiguration {
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
