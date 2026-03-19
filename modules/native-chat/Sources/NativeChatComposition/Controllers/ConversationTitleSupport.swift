import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport

@MainActor
func generateConversationTitleIfNeeded(
    for conversation: Conversation,
    apiKey: String,
    openAIService: OpenAIService,
    saveContext: (String) -> Void
) async {
    guard !apiKey.isEmpty else { return }
    guard conversation.title == "New Chat", conversation.messages.count >= 2 else { return }

    do {
        let title = try await openAIService.generateTitle(
            for: conversationTitlePreview(for: conversation),
            apiKey: apiKey
        )
        conversation.title = title
        saveContext("generateTitleIfNeeded")
    } catch {
        #if DEBUG
        Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
        #endif
    }
}

func conversationTitlePreview(for conversation: Conversation) -> String {
    conversation.messages
        .sorted { $0.createdAt < $1.createdAt }
        .prefix(4)
        .map { "\($0.roleRawValue): \($0.content.prefix(200))" }
        .joined(separator: "\n")
}
