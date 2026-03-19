import Foundation
import ChatDomain
import ChatPersistenceSwiftData
import Testing
import SwiftData
@testable import NativeChatComposition

struct RepositoryTests {
    @MainActor
    @Test func conversationRepositoryFetchesMostRecentConversationAndMessage() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)

        let older = repository.createConversation(configuration: ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        ))
        older.title = "Older"
        older.updatedAt = Date(timeIntervalSince1970: 1)

        let latest = repository.createConversation(configuration: ConversationConfiguration(
            model: .gpt5_4_pro,
            reasoningEffort: .xhigh,
            backgroundModeEnabled: true,
            serviceTier: .flex
        ))
        latest.updatedAt = Date(timeIntervalSince1970: 2)

        let message = Message(role: .user, content: "Hello")
        context.insert(message)
        message.conversation = latest

        try repository.save()

        #expect(try repository.fetchMostRecentConversation()?.id == latest.id)
        #expect(try repository.fetchMessage(id: message.id)?.content == "Hello")
        #expect(try repository.fetchUntitledConversations().map(\.id) == [latest.id])
    }

    @MainActor
    @Test func draftRepositorySeparatesRecoverableAndOrphanedDrafts() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let conversationRepository = ConversationRepository(modelContext: context)
        let draftRepository = DraftRepository(modelContext: context)

        let conversation = conversationRepository.createConversation(configuration: ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        ))

        let completed = Message(role: .assistant, content: "Done", isComplete: true)
        let recoverable = Message(
            role: .assistant,
            content: "",
            responseId: "resp_123",
            isComplete: false
        )
        let orphaned = Message(
            role: .assistant,
            content: "",
            responseId: nil,
            isComplete: false
        )

        for message in [completed, recoverable, orphaned] {
            context.insert(message)
            message.conversation = conversation
        }

        try conversationRepository.save()

        #expect(try draftRepository.fetchIncompleteDrafts().map(\.id).count == 2)
        #expect(try draftRepository.fetchRecoverableDrafts().map(\.id) == [recoverable.id])
        #expect(try draftRepository.fetchOrphanedDrafts().map(\.id) == [orphaned.id])
    }
}
