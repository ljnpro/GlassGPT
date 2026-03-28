/// Captures the full set of user-configurable parameters for a chat conversation.
public struct ConversationConfiguration: Equatable, Sendable {
    /// The language model to use for completions.
    public var model: ModelType
    /// How much computational effort the model should spend on reasoning.
    public var reasoningEffort: ReasoningEffort
    /// The service tier controlling quality-of-service for API requests.
    public var serviceTier: ServiceTier

    /// Creates a new conversation configuration.
    /// - Parameters:
    ///   - model: The language model to use.
    ///   - reasoningEffort: The reasoning effort level.
    ///   - serviceTier: The service tier for API requests.
    public init(
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        serviceTier: ServiceTier
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
    }

    /// Convenience toggle for switching between standard and pro models.
    public var proModeEnabled: Bool {
        get { model == .gpt5_4_pro }
        set { model = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    /// Convenience toggle for switching between standard and flex service tiers.
    public var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }
}
