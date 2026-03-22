import Foundation

/// Describes how streamed reasoning should be presented while an assistant reply is in flight.
public enum ThinkingPresentationState: Equatable, Sendable {
    case reasoning
    case waiting
    case completed

    public static func resolve(
        hasResponseText: Bool,
        isThinking: Bool,
        isAwaitingResponse: Bool
    ) -> ThinkingPresentationState {
        if hasResponseText {
            return .completed
        }

        if isThinking {
            return .reasoning
        }

        if isAwaitingResponse {
            return .waiting
        }

        return .completed
    }

    /// Whether the state should be rendered using live, in-progress affordances.
    public var isLive: Bool {
        switch self {
        case .reasoning, .waiting:
            true
        case .completed:
            false
        }
    }
}
