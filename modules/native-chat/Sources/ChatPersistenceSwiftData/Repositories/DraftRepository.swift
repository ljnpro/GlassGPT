import Foundation
import SwiftData

@MainActor
public final class DraftRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchRecoverableDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId != nil
            }
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetchIncompleteDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false
            }
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetchOrphanedDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId == nil
            }
        )
        return try modelContext.fetch(descriptor)
    }
}
