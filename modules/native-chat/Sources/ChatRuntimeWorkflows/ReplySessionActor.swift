import ChatDomain
import ChatRuntimeModel
import Foundation

/// Actor managing the mutable state of a single assistant reply session.
///
/// All state mutations are serialized through actor isolation, ensuring thread-safe
/// access to the reply buffer, lifecycle, and stream tracking.
public actor ReplySessionActor {
    /// The current runtime state of the reply.
    var state: ReplyRuntimeState
    /// The identifier of the currently active stream, used to discard stale events.
    var activeStreamID: UUID?

    /// Creates a new reply session actor with the given initial state.
    /// - Parameter initialState: The starting runtime state for this session.
    public init(initialState: ReplyRuntimeState) {
        state = initialState
    }

    /// Returns an immutable snapshot of the current runtime state.
    /// - Returns: The current reply runtime state.
    public func snapshot() -> ReplyRuntimeState {
        state
    }

    /// Replaces the entire session state and clears the active stream.
    /// - Parameter nextState: The new state to adopt.
    public func replaceState(with nextState: ReplyRuntimeState) {
        state = nextState
        activeStreamID = nil
    }

    /// Checks whether the given stream identifier matches the currently active stream.
    /// - Parameter streamID: The stream identifier to check.
    /// - Returns: `true` if the stream is currently active.
    public func isActiveStream(_ streamID: UUID) -> Bool {
        activeStreamID == streamID
    }
}
