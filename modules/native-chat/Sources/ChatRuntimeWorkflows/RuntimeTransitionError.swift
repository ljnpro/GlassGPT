import Foundation

/// Errors from invalid runtime state transitions.
public enum RuntimeTransitionError: Error, Sendable {
    /// The transition is not valid for the current lifecycle state.
    case invalidState(current: String, attempted: String)
    /// No active session exists for the given identifier.
    case sessionNotFound
}
