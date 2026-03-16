import Foundation
import SwiftData

@MainActor
final class DraftRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchRecoverableDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId != nil
            }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchIncompleteDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false
            }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchOrphanedDrafts() throws -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId == nil
            }
        )
        return try modelContext.fetch(descriptor)
    }
}
