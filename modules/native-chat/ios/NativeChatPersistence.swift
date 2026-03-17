import Foundation
import SwiftData

/// Shared SwiftData container used by ViewModels and other services.
/// Always uses on-disk persistence. If the store cannot be opened, it preserves
/// the original store files before creating a fresh container.
public enum NativeChatPersistence {
    public static let shared: ModelContainer = createPersistentContainer()

    private static let schema = Schema([
        Conversation.self,
        Message.self
    ])

    private static let storeNames = [
        "default.store",
        "default.store-shm",
        "default.store-wal"
    ]

    private static func createPersistentContainer() -> ModelContainer {
        do {
            return try makeContainer()
        } catch {
            #if DEBUG
            Loggers.persistence.debug("[NativeChatPersistence] Failed to open store: \(error.localizedDescription)")
            #endif
        }

        let recoveryLocation = preserveExistingStoreForRecovery()

        do {
            let container = try makeContainer()
            #if DEBUG
            if let recoveryLocation {
                Loggers.persistence.debug("[NativeChatPersistence] Preserved original store at \(recoveryLocation.path)")
            }
            Loggers.persistence.debug("[NativeChatPersistence] Created fresh store after preserving incompatible files")
            #endif
            return container
        } catch {
            #if DEBUG
            Loggers.persistence.debug("[NativeChatPersistence] Falling back to in-memory store: \(error.localizedDescription)")
            #endif
            return makeInMemoryContainer()
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            preconditionFailure("[NativeChatPersistence] Cannot create fallback in-memory ModelContainer: \(error)")
        }
    }

    private static func preserveExistingStoreForRecovery() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let existingStoreURLs = storeNames
            .map { appSupportURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        guard !existingStoreURLs.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: .now)
            .replacingOccurrences(of: ":", with: "-")

        let recoveryDirectory = appSupportURL
            .appendingPathComponent("NativeChat", isDirectory: true)
            .appendingPathComponent("RecoveredStores", isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: recoveryDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            for storeURL in existingStoreURLs {
                let destinationURL = recoveryDirectory.appendingPathComponent(storeURL.lastPathComponent)
                try fileManager.moveItem(at: storeURL, to: destinationURL)
            }

            return recoveryDirectory
        } catch {
            #if DEBUG
            Loggers.persistence.debug("[NativeChatPersistence] Failed to preserve existing store: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}
