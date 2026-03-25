import ChatApplication
import ChatDomain
import Observation

/// Observable default-setting state for Agent-specific settings.
@Observable
@MainActor
public final class AgentSettingsDefaultsStore {
    /// The user's selected default leader reasoning effort.
    public var defaultLeaderEffort: ReasoningEffort {
        didSet {
            controller.persistDefaultAgentLeaderEffort(defaultLeaderEffort)
        }
    }

    /// The user's selected default worker reasoning effort.
    public var defaultWorkerEffort: ReasoningEffort {
        didSet {
            controller.persistDefaultAgentWorkerEffort(defaultWorkerEffort)
        }
    }

    /// Whether Agent background mode is enabled by default.
    public var defaultBackgroundModeEnabled: Bool {
        didSet {
            controller.persistDefaultAgentBackgroundModeEnabled(defaultBackgroundModeEnabled)
        }
    }

    private var defaultServiceTier: ServiceTier {
        didSet {
            controller.persistDefaultAgentServiceTier(defaultServiceTier)
        }
    }

    private let controller: SettingsSceneController

    /// Whether flex mode is enabled for new Agent conversations.
    public var defaultFlexModeEnabled: Bool {
        get { defaultServiceTier == .flex }
        set { defaultServiceTier = newValue ? .flex : .standard }
    }

    /// The reasoning effort levels available for Agent mode.
    public var availableEfforts: [ReasoningEffort] {
        ModelType.gpt5_4.availableEfforts
    }

    /// Creates Agent default-setting state from persisted values.
    public init(
        defaultLeaderEffort: ReasoningEffort,
        defaultWorkerEffort: ReasoningEffort,
        defaultBackgroundModeEnabled: Bool,
        defaultServiceTier: ServiceTier,
        controller: SettingsSceneController
    ) {
        self.defaultLeaderEffort = defaultLeaderEffort
        self.defaultWorkerEffort = defaultWorkerEffort
        self.defaultBackgroundModeEnabled = defaultBackgroundModeEnabled
        self.defaultServiceTier = defaultServiceTier
        self.controller = controller
    }

    /// The current Agent default conversation configuration.
    public var conversationConfiguration: AgentConversationConfiguration {
        AgentConversationConfiguration(
            leaderReasoningEffort: defaultLeaderEffort,
            workerReasoningEffort: defaultWorkerEffort,
            backgroundModeEnabled: defaultBackgroundModeEnabled,
            serviceTier: defaultServiceTier
        )
    }
}
