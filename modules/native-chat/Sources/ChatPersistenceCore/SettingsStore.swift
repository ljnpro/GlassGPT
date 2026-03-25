import ChatDomain
import Foundation

/// Abstraction over `UserDefaults` for reading and writing settings values.
public protocol SettingsValueStore: AnyObject {
    /// Returns the object associated with the given key, or `nil`.
    func object(forKey defaultName: String) -> Any?
    /// Returns the string associated with the given key, or `nil`.
    func string(forKey defaultName: String) -> String?
    /// Returns the Boolean value associated with the given key.
    func bool(forKey defaultName: String) -> Bool
    /// Sets the value for the given key.
    func set(_ value: Any?, forKey defaultName: String)
}

/// Concrete ``SettingsValueStore`` backed by `UserDefaults`.
public final class UserDefaultsSettingsValueStore: SettingsValueStore {
    private let defaults: UserDefaults

    /// Creates a value store wrapping the given `UserDefaults` instance.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns the object for the given key from `UserDefaults`.
    public func object(forKey defaultName: String) -> Any? {
        defaults.object(forKey: defaultName)
    }

    /// Returns the string for the given key from `UserDefaults`.
    public func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    /// Returns the Boolean value for the given key from `UserDefaults`.
    public func bool(forKey defaultName: String) -> Bool {
        defaults.bool(forKey: defaultName)
    }

    /// Sets the value for the given key in `UserDefaults`.
    public func set(_ value: Any?, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }
}

/// Reads and writes user-facing settings, backed by a ``SettingsValueStore``.
public final class SettingsStore {
    /// `UserDefaults` keys for all persisted settings.
    public enum Keys {
        /// Key for the default model preference.
        public static let defaultModel = "defaultModel"
        /// Key for the default reasoning effort preference.
        public static let defaultEffort = "defaultEffort"
        /// Key for the background mode toggle.
        public static let defaultBackgroundModeEnabled = "defaultBackgroundModeEnabled"
        /// Key for the default service tier preference.
        public static let defaultServiceTier = "defaultServiceTier"
        /// Key for the default Agent leader reasoning effort preference.
        public static let defaultAgentLeaderEffort = "defaultAgentLeaderEffort"
        /// Key for the default Agent worker reasoning effort preference.
        public static let defaultAgentWorkerEffort = "defaultAgentWorkerEffort"
        /// Key for the default Agent background mode preference.
        public static let defaultAgentBackgroundModeEnabled = "defaultAgentBackgroundModeEnabled"
        /// Key for the default Agent service tier preference.
        public static let defaultAgentServiceTier = "defaultAgentServiceTier"
        /// Key for the selected app theme.
        public static let appTheme = "appTheme"
        /// Key for the haptic feedback toggle.
        public static let hapticEnabled = "hapticEnabled"
        /// Key for the Cloudflare gateway toggle.
        public static let cloudflareGatewayEnabled = "cloudflareGatewayEnabled"
        /// Key for the active Cloudflare gateway configuration mode.
        public static let cloudflareGatewayConfigurationMode = "cloudflareGatewayConfigurationMode"
        /// Key for the saved custom Cloudflare gateway base URL.
        public static let customCloudflareGatewayBaseURL = "customCloudflareGatewayBaseURL"
    }

    private let valueStore: any SettingsValueStore

    /// Creates a settings store backed by the given value store.
    public init(valueStore: any SettingsValueStore = UserDefaultsSettingsValueStore(defaults: .standard)) {
        self.valueStore = valueStore
    }

    /// The user's preferred default model. Falls back to `.gpt5_4` if unset.
    public var defaultModel: ModelType {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultModel),
                  let model = ModelType(rawValue: raw)
            else {
                return .gpt5_4
            }
            return model
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultModel)
        }
    }

    /// The user's preferred reasoning effort, clamped to the current model's available efforts.
    public var defaultEffort: ReasoningEffort {
        get {
            let resolvedModel = defaultModel
            guard let raw = valueStore.string(forKey: Keys.defaultEffort),
                  let effort = ReasoningEffort(rawValue: raw)
            else {
                return resolvedModel.defaultEffort
            }

            let correctedEffort = resolvedModel.availableEfforts.contains(effort) ? effort : resolvedModel.defaultEffort
            if correctedEffort != effort {
                valueStore.set(correctedEffort.rawValue, forKey: Keys.defaultEffort)
            }
            return correctedEffort
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultEffort)
        }
    }

    /// Whether background mode is enabled by default for new conversations.
    public var defaultBackgroundModeEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.defaultBackgroundModeEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.defaultBackgroundModeEnabled)
        }
    }

    /// The user's preferred OpenAI service tier. Falls back to `.standard` if unset.
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

    /// The user's preferred default Agent leader reasoning effort.
    public var defaultAgentLeaderEffort: ReasoningEffort {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultAgentLeaderEffort),
                  let effort = ReasoningEffort(rawValue: raw)
            else {
                return .high
            }
            return effort
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultAgentLeaderEffort)
        }
    }

    /// The user's preferred default Agent worker reasoning effort.
    public var defaultAgentWorkerEffort: ReasoningEffort {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultAgentWorkerEffort),
                  let effort = ReasoningEffort(rawValue: raw)
            else {
                return .low
            }
            return effort
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultAgentWorkerEffort)
        }
    }

    /// Whether background mode is enabled by default for new Agent conversations.
    public var defaultAgentBackgroundModeEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.defaultAgentBackgroundModeEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.defaultAgentBackgroundModeEnabled)
        }
    }

    /// The user's preferred Agent service tier. Falls back to `.standard` if unset.
    public var defaultAgentServiceTier: ServiceTier {
        get {
            guard let raw = valueStore.string(forKey: Keys.defaultAgentServiceTier),
                  let tier = ServiceTier(rawValue: raw)
            else {
                return .standard
            }
            return tier
        }
        set {
            valueStore.set(newValue.rawValue, forKey: Keys.defaultAgentServiceTier)
        }
    }

    /// The selected appearance theme. Falls back to `.system` if unset.
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

    /// Whether haptic feedback is enabled. Defaults to `true` if unset.
    public var hapticEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.hapticEnabled) as? Bool ?? true
        }
        set {
            valueStore.set(newValue, forKey: Keys.hapticEnabled)
        }
    }

    /// Whether the Cloudflare AI gateway is enabled. Defaults to `false` if unset.
    public var cloudflareGatewayEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.cloudflareGatewayEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.cloudflareGatewayEnabled)
        }
    }

    /// The persisted Cloudflare gateway configuration mode. Defaults to `.default` if unset.
    public var cloudflareGatewayConfigurationMode: CloudflareGatewayConfigurationMode {
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
    public var customCloudflareGatewayBaseURL: String {
        get {
            valueStore.string(forKey: Keys.customCloudflareGatewayBaseURL) ?? ""
        }
        set {
            valueStore.set(newValue, forKey: Keys.customCloudflareGatewayBaseURL)
        }
    }

    /// Builds a ``ConversationConfiguration`` from the current default settings.
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

    /// Builds an ``AgentConversationConfiguration`` from the current Agent default settings.
    public var defaultAgentConversationConfiguration: AgentConversationConfiguration {
        AgentConversationConfiguration(
            leaderReasoningEffort: defaultAgentLeaderEffort,
            workerReasoningEffort: defaultAgentWorkerEffort,
            backgroundModeEnabled: defaultAgentBackgroundModeEnabled,
            serviceTier: defaultAgentServiceTier
        )
    }
}
