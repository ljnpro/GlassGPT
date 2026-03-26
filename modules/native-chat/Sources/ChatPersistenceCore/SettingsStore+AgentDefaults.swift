import ChatDomain
import Foundation

public extension SettingsStore {
    /// The user's preferred default Agent leader reasoning effort.
    var defaultAgentLeaderEffort: ReasoningEffort {
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
    var defaultAgentWorkerEffort: ReasoningEffort {
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
    var defaultAgentBackgroundModeEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.defaultAgentBackgroundModeEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.defaultAgentBackgroundModeEnabled)
        }
    }

    /// The user's preferred Agent service tier. Falls back to `.standard` if unset.
    var defaultAgentServiceTier: ServiceTier {
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

    /// Builds an ``AgentConversationConfiguration`` from the current Agent default settings.
    var defaultAgentConversationConfiguration: AgentConversationConfiguration {
        AgentConversationConfiguration(
            leaderReasoningEffort: defaultAgentLeaderEffort,
            workerReasoningEffort: defaultAgentWorkerEffort,
            backgroundModeEnabled: defaultAgentBackgroundModeEnabled,
            serviceTier: defaultAgentServiceTier
        )
    }
}
