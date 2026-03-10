import Foundation
import SwiftData

enum NativeChatPersistence {
    static let shared: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }()
}
