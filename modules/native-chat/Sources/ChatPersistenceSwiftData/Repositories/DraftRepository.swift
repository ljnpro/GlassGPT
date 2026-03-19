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
    public func fetchRecoverableDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId != nil
            }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns all incomplete messages regardless of recovery eligibility.
    public func fetchIncompleteDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false
            }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns incomplete messages without a `responseId`, which cannot be recovered from the API.
    public func fetchOrphanedDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId == nil
            }
        )
        return try modelContext.fetch(descriptor)
    }
}
