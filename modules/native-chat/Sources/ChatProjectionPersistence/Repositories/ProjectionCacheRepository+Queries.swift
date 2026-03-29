import ChatDomain
import ChatPersistenceCore
import Foundation
import SwiftData

@MainActor
public extension ProjectionCacheRepository {
    func fetchConversation(
        serverID: String,
        accountID: String
    ) throws(PersistenceError) -> Conversation? {
        do {
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conversation in
                    conversation.serverID == serverID && conversation.syncAccountID == accountID
                }
            )
            return try modelContext.fetch(descriptor).first
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }

    func fetchConversations(
        accountID: String,
        mode: ConversationMode? = nil
    ) throws(PersistenceError) -> [Conversation] {
        do {
            if let mode {
                let descriptor = switch mode {
                case .chat:
                    FetchDescriptor<Conversation>(
                        predicate: #Predicate<Conversation> { conversation in
                            conversation.syncAccountID == accountID && conversation.modeRawValue == nil
                        },
                        sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                    )
                case .agent:
                    FetchDescriptor<Conversation>(
                        predicate: #Predicate<Conversation> { conversation in
                            conversation.syncAccountID == accountID && conversation.modeRawValue == "agent"
                        },
                        sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                    )
                }
                return try modelContext.fetch(descriptor)
            }

            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate<Conversation> { conversation in
                    conversation.syncAccountID == accountID
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            throw .migrationFailure(underlying: error)
        }
    }
}
