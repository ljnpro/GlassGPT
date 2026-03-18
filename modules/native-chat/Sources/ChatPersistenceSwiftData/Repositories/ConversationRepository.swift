import ChatDomain
import Foundation
import SwiftData

@MainActor
public final class ConversationRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func save() throws {
        try modelContext.save()
    }

    public func createConversation(configuration: ConversationConfiguration) -> Conversation {
        let conversation = Conversation(
            model: configuration.model.rawValue,
            reasoningEffort: configuration.reasoningEffort.rawValue,
            backgroundModeEnabled: configuration.backgroundModeEnabled,
            serviceTierRawValue: configuration.serviceTier.rawValue
        )
        modelContext.insert(conversation)
        return conversation
    }

    public func fetchMostRecentConversation() throws -> Conversation? {
        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    public func fetchMostRecentConversationWithMessages() throws -> Conversation? {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first(where: { !$0.messages.isEmpty })
    }

    public func fetchUntitledConversations() throws -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conversation in
                conversation.title == "New Chat"
            }
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetchMessage(id: UUID) throws -> Message? {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func delete(_ message: Message) {
        modelContext.delete(message)
    }
}
