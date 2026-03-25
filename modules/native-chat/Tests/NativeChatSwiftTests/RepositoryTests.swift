import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import SwiftData
import Testing
@testable import NativeChatComposition

struct RepositoryTests {
    @MainActor
    @Test func `conversation repository fetches most recent conversation and message`() throws {
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
    @Test func `conversation repository restores most recent conversation with messages by mode`() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)

        let chatConversation = repository.createConversation(configuration: ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        ))
        chatConversation.updatedAt = Date(timeIntervalSince1970: 10)

        let agentConversation = repository.createConversation(configuration: ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: true,
            serviceTier: .flex
        ))
        agentConversation.mode = .agent
        agentConversation.updatedAt = Date(timeIntervalSince1970: 20)

        let chatMessage = Message(role: .assistant, content: "Chat answer", conversation: chatConversation)
        let agentMessage = Message(role: .assistant, content: "Agent answer", conversation: agentConversation)
        chatConversation.messages = [chatMessage]
        agentConversation.messages = [agentMessage]
        context.insert(chatMessage)
        context.insert(agentMessage)

        try repository.save()

        #expect(try repository.fetchMostRecentConversationWithMessages(mode: .chat)?.id == chatConversation.id)
        #expect(try repository.fetchMostRecentConversationWithMessages(mode: .agent)?.id == agentConversation.id)
    }

    @MainActor
    @Test func `draft repository separates recoverable and orphaned drafts`() throws {
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
        let agentConversation = conversationRepository.createConversation(configuration: ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        ))
        agentConversation.mode = .agent

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
        let agentRecoverable = Message(
            role: .assistant,
            content: "",
            responseId: "resp_agent",
            isComplete: false
        )

        for message in [completed, recoverable, orphaned] {
            context.insert(message)
            message.conversation = conversation
        }
        context.insert(agentRecoverable)
        agentRecoverable.conversation = agentConversation

        try conversationRepository.save()

        #expect(try draftRepository.fetchIncompleteDrafts().map(\.id).count == 3)
        #expect(try Set(draftRepository.fetchRecoverableDrafts().map(\.id)) == Set([recoverable.id, agentRecoverable.id]))
        #expect(try draftRepository.fetchOrphanedDrafts().map(\.id) == [orphaned.id])
        #expect(try draftRepository.fetchRecoverableDrafts(mode: .chat).map(\.id) == [recoverable.id])
        #expect(try draftRepository.fetchRecoverableDrafts(mode: .agent).map(\.id) == [agentRecoverable.id])
    }
}
