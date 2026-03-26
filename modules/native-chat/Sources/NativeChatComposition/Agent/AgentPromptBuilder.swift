import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

enum AgentPromptBuilder {
    static func visibleConversationInput(
        from messages: [Message]
    ) -> [ResponsesInputMessageDTO] {
        let requestMessages = messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .filter { $0.role == .user || ($0.role == .assistant && $0.isComplete) }
            .map {
                APIMessage(
                    role: $0.role,
                    content: $0.content,
                    imageData: $0.imageData,
                    fileAttachments: $0.fileAttachments
                )
            }

        return OpenAIRequestFactory.buildInputMessages(messages: requestMessages)
    }
}
