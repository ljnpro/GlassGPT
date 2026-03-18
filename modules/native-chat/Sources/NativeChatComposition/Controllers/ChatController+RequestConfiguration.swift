import ChatPersistenceSwiftData
import ChatDomain
import Foundation
import OpenAITransport

@MainActor
extension ChatController {
    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier) {
        conversationCoordinator.sessionRequestConfiguration(for: conversation)
    }

    func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage] {
        conversationCoordinator.buildRequestMessages(for: conversation, excludingDraft: draftID)
    }
}
