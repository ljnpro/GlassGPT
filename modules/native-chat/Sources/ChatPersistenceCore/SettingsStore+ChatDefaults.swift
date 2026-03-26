import ChatDomain
import Foundation

public extension SettingsStore {
    /// The user's preferred default model. Falls back to `.gpt5_4` if unset.
    var defaultModel: ModelType {
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
    var defaultEffort: ReasoningEffort {
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
    var defaultBackgroundModeEnabled: Bool {
        get {
            valueStore.object(forKey: Keys.defaultBackgroundModeEnabled) as? Bool ?? false
        }
        set {
            valueStore.set(newValue, forKey: Keys.defaultBackgroundModeEnabled)
        }
    }

    /// The user's preferred OpenAI service tier. Falls back to `.standard` if unset.
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

    /// Builds a ``ConversationConfiguration`` from the current default settings.
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
