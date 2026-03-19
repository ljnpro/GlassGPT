import ChatDomain
import Foundation
import SwiftData

/// Repository for creating, querying, and deleting ``Conversation`` and ``Message`` entities.
///
/// All methods are `@MainActor`-isolated because they operate on a `ModelContext`.
@MainActor
public final class ConversationRepository {
    private let modelContext: ModelContext

    /// Creates a repository targeting the given SwiftData model context.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Persists all pending changes in the model context.
    public func save() throws {
        try modelContext.save()
    }

    /// Creates and inserts a new conversation configured with the given parameters.
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

    /// Returns the most recently updated conversation, or `nil` if none exist.
    public func fetchMostRecentConversation() throws -> Conversation? {
        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Returns the most recently updated conversation that has at least one message.
    public func fetchMostRecentConversationWithMessages() throws -> Conversation? {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first(where: { !$0.messages.isEmpty })
    }

    /// Returns all conversations whose title is still "New Chat".
    public func fetchUntitledConversations() throws -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conversation in
                conversation.title == "New Chat"
            }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches a single message by its unique identifier.
    public func fetchMessage(id: UUID) throws -> Message? {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Deletes the given message from the model context.
    public func delete(_ message: Message) {
        modelContext.delete(message)
    }
}
