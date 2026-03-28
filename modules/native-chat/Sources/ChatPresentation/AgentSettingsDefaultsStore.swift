import ChatDomain
import ChatPersistenceCore
import Observation

/// Observable default-setting state for Agent-specific settings.
@Observable
@MainActor
public final class AgentSettingsDefaultsStore {
    /// The user's selected default leader reasoning effort.
    public var defaultLeaderEffort: ReasoningEffort {
        didSet {
            settingsStore.defaultAgentLeaderEffort = defaultLeaderEffort
        }
    }

    /// The user's selected default worker reasoning effort.
    public var defaultWorkerEffort: ReasoningEffort {
        didSet {
            settingsStore.defaultAgentWorkerEffort = defaultWorkerEffort
        }
    }

    private var defaultServiceTier: ServiceTier {
        didSet {
            settingsStore.defaultAgentServiceTier = defaultServiceTier
        }
    }

    private let settingsStore: SettingsStore

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
        settingsStore: SettingsStore
    ) {
        self.settingsStore = settingsStore
        defaultLeaderEffort = settingsStore.defaultAgentLeaderEffort
        defaultWorkerEffort = settingsStore.defaultAgentWorkerEffort
        defaultServiceTier = settingsStore.defaultAgentServiceTier
    }

    /// The current Agent default conversation configuration.
    public var conversationConfiguration: AgentConversationConfiguration {
        AgentConversationConfiguration(
            leaderReasoningEffort: defaultLeaderEffort,
            workerReasoningEffort: defaultWorkerEffort,
            serviceTier: defaultServiceTier
        )
    }
}
