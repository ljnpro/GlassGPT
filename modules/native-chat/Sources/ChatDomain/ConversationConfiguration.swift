public struct ConversationConfiguration: Equatable, Sendable {
    public var model: ModelType
    public var reasoningEffort: ReasoningEffort
    public var backgroundModeEnabled: Bool
    public var serviceTier: ServiceTier

    public init(
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.backgroundModeEnabled = backgroundModeEnabled
        self.serviceTier = serviceTier
    }

    public var proModeEnabled: Bool {
        get { model == .gpt5_4_pro }
        set { model = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    public var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }
}
