import Foundation
import SwiftData

/// Shared SwiftData container used by ViewModels and other services.
/// Always uses on-disk persistence. If the store cannot be opened due to
/// schema changes, it deletes the old store and creates a fresh one.
enum NativeChatPersistence {
    static let shared: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self
        ])

        // First attempt: open existing store
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            #if DEBUG
            print("[NativeChatPersistence] Failed to open store: \(error.localizedDescription)")
            print("[NativeChatPersistence] Deleting old store and recreating…")
            #endif
        }

        // Delete corrupted store files and retry
        deleteExistingStore()

        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("[NativeChatPersistence] Cannot create ModelContainer: \(error)")
        }
    }()

    private static func deleteExistingStore() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let storeNames = ["default.store", "default.store-shm", "default.store-wal"]
        for name in storeNames {
            let url = appSupportURL.appendingPathComponent(name)
            try? fileManager.removeItem(at: url)
        }
    }
}
