import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
enum ChatRecoverySessionFactory {
    static func makeSession(
        for message: Message,
        conversationID: UUID,
        configuration: (ModelType, ReasoningEffort, ServiceTier),
        apiKey: String
    ) -> ReplySession {
        ReplySession(
            assistantReplyID: AssistantReplyID(rawValue: message.id),
            message: message,
            conversationID: conversationID,
            request: ResponseRequestContext(
                apiKey: apiKey,
                messages: nil,
                model: configuration.0,
                effort: configuration.1,
                usesBackgroundMode: message.usedBackgroundMode,
                serviceTier: configuration.2
            )
        )
    }
}
