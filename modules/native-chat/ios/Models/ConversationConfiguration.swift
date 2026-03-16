import Foundation

struct ConversationConfiguration: Equatable, Sendable {
    var model: ModelType
    var reasoningEffort: ReasoningEffort
    var backgroundModeEnabled: Bool
    var serviceTier: ServiceTier

    var proModeEnabled: Bool {
        get { model == .gpt5_4_pro }
        set { model = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }
}
