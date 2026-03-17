import Foundation

@MainActor
final class ChatSessionRegistry {
    private var sessions: [UUID: ResponseSession] = [:]
    private(set) var visibleMessageID: UUID?

    var currentVisibleSession: ResponseSession? {
        guard let visibleMessageID else { return nil }
        return sessions[visibleMessageID]
    }

    var allSessions: [ResponseSession] {
        Array(sessions.values)
    }

    func session(for messageID: UUID) -> ResponseSession? {
        sessions[messageID]
    }

    func contains(_ session: ResponseSession) -> Bool {
        sessions[session.messageID] === session
    }

    func register(
        _ session: ResponseSession,
        visible: Bool,
        cancelExisting: (ResponseSession) -> Void
    ) {
        if let existing = sessions[session.messageID], existing !== session {
            cancelExisting(existing)
        }

        sessions[session.messageID] = session

        if visible {
            visibleMessageID = session.messageID
        }
    }

    func bindVisibleSession(messageID: UUID?) {
        visibleMessageID = messageID
    }

    func remove(_ session: ResponseSession, cancel: (ResponseSession) -> Void) {
        cancel(session)
        sessions.removeValue(forKey: session.messageID)

        if visibleMessageID == session.messageID {
            visibleMessageID = nil
        }
    }

    func removeAll(cancel: (ResponseSession) -> Void) {
        let sessionsToCancel = Array(sessions.values)
        sessions.removeAll()
        visibleMessageID = nil

        for session in sessionsToCancel {
            cancel(session)
        }
    }

    func hasVisibleSession(in conversationID: UUID?) -> Bool {
        guard
            let conversationID,
            let visibleMessageID,
            let session = sessions[visibleMessageID]
        else {
            return false
        }

        return session.conversationID == conversationID
    }

    func activeMessageID(
        in conversation: Conversation,
        fallbackMessages: [Message]
    ) -> UUID? {
        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { sessions[$0.id] != nil }) {
            return message.id
        }

        return fallbackMessages
            .last(where: { sessions[$0.id] != nil })?
            .id
    }
}
