import ChatDomain
import ChatPersistenceCore
import Observation

/// Observable default-setting state for the settings scene.
///
/// Owns persisted defaults and the model-effort compatibility invariant.
@Observable
@MainActor
public final class SettingsDefaultsStore {
    /// The user's selected default reasoning effort.
    public var defaultEffort: ReasoningEffort {
        didSet {
            settingsStore.defaultEffort = defaultEffort
        }
    }

    /// The selected app theme.
    public var appTheme: AppTheme {
        didSet {
            settingsStore.appTheme = appTheme
        }
    }

    /// Whether haptic feedback is enabled.
    public var hapticEnabled: Bool {
        didSet {
            settingsStore.hapticEnabled = hapticEnabled
        }
    }

    private var defaultModel: ModelType {
        didSet {
            settingsStore.defaultModel = defaultModel
        }
    }

    private var defaultServiceTier: ServiceTier {
        didSet {
            settingsStore.defaultServiceTier = defaultServiceTier
        }
    }

    private let settingsStore: SettingsStore

    /// Whether Pro mode is enabled. Toggling this switches between `.gpt5_4_pro` and `.gpt5_4`.
    public var defaultProModeEnabled: Bool {
        get { defaultModel == .gpt5_4_pro }
        set { applyDefaultModel(newValue ? .gpt5_4_pro : .gpt5_4) }
    }

    /// Whether flex mode is enabled. Toggling this switches between `.flex` and `.standard`.
    public var defaultFlexModeEnabled: Bool {
        get { defaultServiceTier == .flex }
        set { defaultServiceTier = newValue ? .flex : .standard }
    }

    /// The reasoning efforts available for the currently selected model.
    public var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    /// Creates default-setting state from persisted values.
    public init(
        settingsStore: SettingsStore
    ) {
        self.settingsStore = settingsStore
        defaultModel = settingsStore.defaultModel
        defaultEffort = settingsStore.defaultEffort
        defaultServiceTier = settingsStore.defaultServiceTier
        appTheme = settingsStore.appTheme
        hapticEnabled = settingsStore.hapticEnabled
    }

    private func applyDefaultModel(_ model: ModelType) {
        if defaultModel != model {
            defaultModel = model
        }
        guard !defaultModel.availableEfforts.contains(defaultEffort) else { return }
        defaultEffort = defaultModel.defaultEffort
    }
}
