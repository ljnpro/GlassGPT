import ChatApplication
import ChatDomain
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
            controller.persistDefaultEffort(defaultEffort)
        }
    }

    /// Whether background mode is enabled by default.
    public var defaultBackgroundModeEnabled: Bool {
        didSet {
            controller.persistDefaultBackgroundModeEnabled(defaultBackgroundModeEnabled)
        }
    }

    /// The selected app theme.
    public var appTheme: AppTheme {
        didSet {
            controller.persistAppTheme(appTheme)
        }
    }

    /// Whether haptic feedback is enabled.
    public var hapticEnabled: Bool {
        didSet {
            controller.persistHapticEnabled(hapticEnabled)
        }
    }

    /// Whether the Cloudflare gateway is enabled.
    public var cloudflareEnabled: Bool {
        didSet {
            guard cloudflareEnabled != oldValue else { return }
            controller.persistCloudflareEnabled(cloudflareEnabled)
            cloudflareGatewayObserver?(cloudflareEnabled)
        }
    }

    private var defaultModel: ModelType {
        didSet {
            controller.persistDefaultModel(defaultModel)
        }
    }

    private var defaultServiceTier: ServiceTier {
        didSet {
            controller.persistDefaultServiceTier(defaultServiceTier)
        }
    }

    private let controller: SettingsSceneController
    private var cloudflareGatewayObserver: (@MainActor (Bool) -> Void)?

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
        defaultModel: ModelType,
        defaultEffort: ReasoningEffort,
        defaultBackgroundModeEnabled: Bool,
        defaultServiceTier: ServiceTier,
        appTheme: AppTheme,
        hapticEnabled: Bool,
        cloudflareEnabled: Bool,
        controller: SettingsSceneController
    ) {
        self.defaultModel = defaultModel
        self.defaultEffort = defaultEffort
        self.defaultBackgroundModeEnabled = defaultBackgroundModeEnabled
        self.defaultServiceTier = defaultServiceTier
        self.appTheme = appTheme
        self.hapticEnabled = hapticEnabled
        self.cloudflareEnabled = cloudflareEnabled
        self.controller = controller
    }

    /// Registers a callback to run whenever the Cloudflare gateway toggle changes.
    public func observeCloudflareGatewayChanges(
        _ observer: @escaping @MainActor (Bool) -> Void
    ) {
        cloudflareGatewayObserver = observer
    }

    private func applyDefaultModel(_ model: ModelType) {
        if defaultModel != model {
            defaultModel = model
        }
        guard !defaultModel.availableEfforts.contains(defaultEffort) else { return }
        defaultEffort = defaultModel.defaultEffort
    }
}
