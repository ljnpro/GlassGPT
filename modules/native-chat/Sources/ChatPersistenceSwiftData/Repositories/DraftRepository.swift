import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData

/// Repository for querying incomplete (draft) assistant messages used in session recovery.
///
/// All methods are `@MainActor`-isolated because they operate on a `ModelContext`.
@MainActor
public final class DraftRepository {
    private let modelContext: ModelContext

    /// Creates a repository targeting the given SwiftData model context.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Returns incomplete messages that have a `responseId`, making them eligible for recovery.
    public func fetchRecoverableDrafts() throws(PersistenceError) -> [Message] {
        try fetchRecoverableDrafts(mode: nil)
    }

    /// Returns incomplete messages that have a `responseId`, filtered by conversation mode when provided.
    public func fetchRecoverableDrafts(
        mode: ConversationMode?
    ) throws(PersistenceError) -> [Message] {
        do {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { message in
                    message.isComplete == false && message.responseId != nil
                }
            )
            return try filteredMessages(using: descriptor, mode: mode)
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Returns all incomplete messages regardless of recovery eligibility.
    public func fetchIncompleteDrafts() throws(PersistenceError) -> [Message] {
        try fetchIncompleteDrafts(mode: nil)
    }

    /// Returns all incomplete messages, filtered by conversation mode when provided.
    public func fetchIncompleteDrafts(
        mode: ConversationMode?
    ) throws(PersistenceError) -> [Message] {
        do {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { message in
                    message.isComplete == false
                }
            )
            return try filteredMessages(using: descriptor, mode: mode)
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    /// Returns incomplete messages without a `responseId`, which cannot be recovered from the API.
    public func fetchOrphanedDrafts() throws(PersistenceError) -> [Message] {
        try fetchOrphanedDrafts(mode: nil)
    }

    /// Returns incomplete messages without a `responseId`, filtered by conversation mode when provided.
    public func fetchOrphanedDrafts(
        mode: ConversationMode?
    ) throws(PersistenceError) -> [Message] {
        do {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { message in
                    message.isComplete == false && message.responseId == nil
                }
            )
            return try filteredMessages(using: descriptor, mode: mode)
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    private func filteredMessages(
        using descriptor: FetchDescriptor<Message>,
        mode: ConversationMode?
    ) throws -> [Message] {
        let messages = try modelContext.fetch(descriptor)
        guard let mode else {
            return messages
        }
        return messages.filter { ($0.conversation?.mode ?? .chat) == mode }
    }
}
