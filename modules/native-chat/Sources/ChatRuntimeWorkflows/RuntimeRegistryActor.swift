import ChatDomain
import ChatRuntimeModel
import Foundation

public actor RuntimeRegistryActor {
    private var sessions: [AssistantReplyID: ReplySessionActor] = [:]

    public init() {}

    public func register(_ session: ReplySessionActor, for replyID: AssistantReplyID) {
        sessions[replyID] = session
    }

    @discardableResult
    public func startSession(
        messageID: UUID,
        conversationID: UUID
    ) -> AssistantReplyID {
        let replyID = AssistantReplyID(rawValue: messageID)
        registerSession(replyID: replyID, messageID: messageID, conversationID: conversationID)
        return replyID
    }

    public func startSession(
        replyID: AssistantReplyID,
        messageID: UUID,
        conversationID: UUID
    ) {
        registerSession(replyID: replyID, messageID: messageID, conversationID: conversationID)
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

    public func session(for replyID: AssistantReplyID) -> ReplySessionActor? {
        sessions[replyID]
    }

    public func contains(_ replyID: AssistantReplyID) -> Bool {
        sessions[replyID] != nil
    }

    public func remove(_ replyID: AssistantReplyID) {
        sessions.removeValue(forKey: replyID)
    }

    public func activeReplyIDs() -> [AssistantReplyID] {
        Array(sessions.keys)
    }
}
