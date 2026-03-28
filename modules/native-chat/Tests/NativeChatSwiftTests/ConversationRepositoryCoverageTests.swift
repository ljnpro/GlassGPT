import ChatDomain
import Foundation
import SwiftData
import Testing
@testable import ChatPersistenceSwiftData

struct ConversationRepositoryCoverageTests {
    @MainActor
    @Test
    func `conversation repository creates fetches filters and deletes conversations`() throws {
        let container = try makeConversationRepositoryContainer()
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)

        let chatConfiguration = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .medium,
            serviceTier: .standard
        )
        let agentConfiguration = ConversationConfiguration(
            model: .gpt5_4_pro,
            reasoningEffort: .high,
            serviceTier: .flex
        )

        let untitled = repository.createConversation(configuration: chatConfiguration)
        untitled.updatedAt = .init(timeIntervalSince1970: 1)

        let chat = repository.createConversation(configuration: chatConfiguration)
        chat.title = "Chat"
        chat.updatedAt = .init(timeIntervalSince1970: 3)
        let chatMessage = Message(
            role: .assistant,
            content: "done",
            conversation: chat,
            isComplete: true
        )
        context.insert(chatMessage)
        chat.messages.append(chatMessage)

        let agent = repository.createConversation(configuration: agentConfiguration)
        agent.mode = .agent
        agent.title = "Agent"
        agent.updatedAt = .init(timeIntervalSince1970: 5)
        let draftMessage = Message(
            role: .assistant,
            content: "draft",
            conversation: agent,
            isComplete: false
        )
        context.insert(draftMessage)
        agent.messages.append(draftMessage)

        try repository.save()

        #expect(try repository.fetchMostRecentConversation()?.id == agent.id)
        #expect(try repository.fetchMostRecentConversationWithMessages()?.id == agent.id)
        #expect(try repository.fetchMostRecentConversationWithMessages(mode: .chat)?.id == chat.id)
        #expect(try repository.fetchMostRecentConversationWithMessages(mode: .agent)?.id == agent.id)
        #expect(try repository.fetchConversationsWithIncompleteDrafts(mode: .agent).map(\.id) == [agent.id])
        #expect(try repository.fetchUntitledConversations().map(\.id) == [untitled.id])
        #expect(try repository.fetchConversation(id: chat.id)?.title == "Chat")
        #expect(try repository.fetchMessage(id: draftMessage.id)?.content == "draft")

        repository.delete(draftMessage)
        try repository.save()
        #expect(try repository.fetchMessage(id: draftMessage.id) == nil)
        #expect(try repository.fetchConversationsWithIncompleteDrafts(mode: nil).isEmpty)
    }
}

@MainActor
private func makeConversationRepositoryContainer() throws -> ModelContainer {
    let schema = Schema([Conversation.self, Message.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
