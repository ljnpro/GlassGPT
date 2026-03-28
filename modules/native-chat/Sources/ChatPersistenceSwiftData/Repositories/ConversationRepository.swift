import ChatDomain
import ChatPersistenceCore
import Foundation
import os
import SwiftData

/// Repository for creating, querying, and deleting ``Conversation`` and ``Message`` entities.
///
/// All methods are `@MainActor`-isolated because they operate on a `ModelContext`.
private let conversationRepoSignposter = OSSignposter(subsystem: "GlassGPT", category: "persistence")

@MainActor
public final class ConversationRepository {
    private let modelContext: ModelContext

    /// Creates a repository targeting the given SwiftData model context.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Persists all pending changes in the model context.
    public func save() throws(PersistenceError) {
        do {
            try modelContext.save()
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Creates and inserts a new conversation configured with the given parameters.
    public func createConversation(configuration: ConversationConfiguration) -> Conversation {
        let conversation = Conversation(
            model: configuration.model.rawValue,
            reasoningEffort: configuration.reasoningEffort.rawValue,
            serviceTierRawValue: configuration.serviceTier.rawValue
        )
        modelContext.insert(conversation)
        return conversation
    }

    /// Returns the most recently updated conversation, or `nil` if none exist.
    public func fetchMostRecentConversation() throws(PersistenceError) -> Conversation? {
        let signpostID = conversationRepoSignposter.makeSignpostID()
        let signpostState = conversationRepoSignposter.beginInterval("FetchMostRecentConversation", id: signpostID)
        defer { conversationRepoSignposter.endInterval("FetchMostRecentConversation", signpostState) }

        do {
            var descriptor = FetchDescriptor<Conversation>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Returns the most recently updated conversation that has at least one message.
    public func fetchMostRecentConversationWithMessages() throws(PersistenceError) -> Conversation? {
        try fetchMostRecentConversationWithMessages(mode: nil)
    }

    /// Returns the most recently updated conversation with at least one message for the requested mode.
    public func fetchMostRecentConversationWithMessages(
        mode: ConversationMode?
    ) throws(PersistenceError) -> Conversation? {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).first(where: { conversation in
                guard !conversation.messages.isEmpty else {
                    return false
                }
                guard let mode else {
                    return true
                }
                return conversation.mode == mode
            })
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Returns conversations with at least one incomplete assistant draft for the requested mode.
    public func fetchConversationsWithIncompleteDrafts(
        mode: ConversationMode?
    ) throws(PersistenceError) -> [Conversation] {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).filter { conversation in
                guard conversation.messages.contains(where: { $0.role == .assistant && !$0.isComplete }) else {
                    return false
                }
                guard let mode else {
                    return true
                }
                return conversation.mode == mode
            }
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Returns all conversations whose title is still "New Chat".
    public func fetchUntitledConversations() throws(PersistenceError) -> [Conversation] {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conversation in
                    conversation.title == "New Chat"
                }
            )
            return try modelContext.fetch(descriptor)
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Fetches a single message by its unique identifier.
    public func fetchMessage(id: UUID) throws(PersistenceError) -> Message? {
        do {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { $0.id == id }
            )
            return try modelContext.fetch(descriptor).first
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Fetches a single conversation by its unique identifier.
    public func fetchConversation(id: UUID) throws(PersistenceError) -> Conversation? {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { $0.id == id }
            )
            return try modelContext.fetch(descriptor).first
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Deletes the given message from the model context.
    public func delete(_ message: Message) {
        modelContext.delete(message)
    }
}
