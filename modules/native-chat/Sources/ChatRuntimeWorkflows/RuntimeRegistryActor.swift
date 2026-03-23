import ChatDomain
import ChatRuntimeModel
import Foundation

/// Actor that manages a registry of active reply sessions keyed by their reply identifiers.
///
/// Provides thread-safe creation, lookup, and removal of ``ReplySessionActor`` instances.
public actor RuntimeRegistryActor {
    private var sessions: [AssistantReplyID: ReplySessionActor] = [:]

    /// Creates a new empty runtime registry.
    public init() {}

    /// Registers an existing session actor for the given reply identifier.
    /// - Parameters:
    ///   - session: The session actor to register.
    ///   - replyID: The reply identifier to associate with the session.
    public func register(_ session: ReplySessionActor, for replyID: AssistantReplyID) {
        sessions[replyID] = session
    }

    /// Creates and registers a new session, deriving the reply ID from the message ID.
    /// - Parameters:
    ///   - messageID: The message identifier, also used as the reply ID.
    ///   - conversationID: The owning conversation identifier.
    /// - Returns: The generated assistant reply identifier.
    @discardableResult
    public func startSession(
        messageID: UUID,
        conversationID: UUID
    ) -> AssistantReplyID {
        let replyID = AssistantReplyID(rawValue: messageID)
        registerSession(replyID: replyID, messageID: messageID, conversationID: conversationID)
        return replyID
    }

    /// Creates and registers a new session with an explicit reply identifier.
    /// - Parameters:
    ///   - replyID: The reply identifier to use.
    ///   - messageID: The persisted message identifier.
    ///   - conversationID: The owning conversation identifier.
    public func startSession(
        replyID: AssistantReplyID,
        messageID: UUID,
        conversationID: UUID
    ) {
        registerSession(replyID: replyID, messageID: messageID, conversationID: conversationID)
    }

    /// Creates and registers a new session from a prepared runtime state snapshot.
    /// - Parameter initialState: The runtime state to seed into the new session actor.
    public func startSession(initialState: ReplyRuntimeState) {
        sessions[initialState.assistantReplyID] = ReplySessionActor(initialState: initialState)
    }

    private func registerSession(
        replyID: AssistantReplyID,
        messageID: UUID,
        conversationID: UUID
    ) {
        sessions[replyID] = ReplySessionActor(
            initialState: ReplyRuntimeState(
                assistantReplyID: replyID,
                messageID: messageID,
                conversationID: conversationID,
                lifecycle: .preparingInput
            )
        )
    }

    /// Returns the session actor for the given reply identifier, if registered.
    /// - Parameter replyID: The reply identifier to look up.
    /// - Returns: The session actor, or `nil` if not found.
    public func session(for replyID: AssistantReplyID) -> ReplySessionActor? {
        sessions[replyID]
    }

    /// Checks whether a session is registered for the given reply identifier.
    /// - Parameter replyID: The reply identifier to check.
    /// - Returns: `true` if a session exists for this identifier.
    public func contains(_ replyID: AssistantReplyID) -> Bool {
        sessions[replyID] != nil
    }

    /// Removes the session for the given reply identifier.
    /// - Parameter replyID: The reply identifier to remove.
    public func remove(_ replyID: AssistantReplyID) {
        sessions.removeValue(forKey: replyID)
    }

    /// Removes all currently registered reply sessions.
    public func removeAll() {
        sessions.removeAll()
    }

    /// Returns all currently registered reply identifiers.
    /// - Returns: An array of active reply identifiers.
    public func activeReplyIDs() -> [AssistantReplyID] {
        Array(sessions.keys)
    }
}
