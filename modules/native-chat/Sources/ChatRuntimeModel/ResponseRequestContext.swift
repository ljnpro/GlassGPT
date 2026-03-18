import ChatDomain
import Foundation

public struct ResponseRequestContext: Equatable, Sendable {
    public let apiKey: String
    public let messages: [ChatRequestMessage]?
    public let model: ModelType
    public let effort: ReasoningEffort
    public let usesBackgroundMode: Bool
    public let serviceTier: ServiceTier

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
