import ChatDomain
import Foundation

/// Encapsulates the parameters needed to make an API response request.
public struct ResponseRequestContext: Equatable, Sendable {
    /// The API key for authentication.
    public let apiKey: String
    /// The message history to send, or `nil` for recovery requests that resume by response ID.
    public let messages: [ChatRequestMessage]?
    /// The model to use for the completion.
    public let model: ModelType
    /// The reasoning effort level.
    public let effort: ReasoningEffort
    /// Whether this request should use background mode.
    public let usesBackgroundMode: Bool
    /// The service tier for this request.
    public let serviceTier: ServiceTier

    /// Creates a new response request context.
    /// - Parameters:
    ///   - apiKey: The API authentication key.
    ///   - messages: The message history, or `nil` for resumption.
    ///   - model: The model to use.
    ///   - effort: The reasoning effort level.
    ///   - usesBackgroundMode: Whether background mode is enabled.
    ///   - serviceTier: The service tier.
    public init(
        apiKey: String,
        messages: [ChatRequestMessage]?,
        model: ModelType,
        effort: ReasoningEffort,
        usesBackgroundMode: Bool,
        serviceTier: ServiceTier
    ) {
        self.apiKey = apiKey
        self.messages = messages
        self.model = model
        self.effort = effort
        self.usesBackgroundMode = usesBackgroundMode
        self.serviceTier = serviceTier
    }
}
