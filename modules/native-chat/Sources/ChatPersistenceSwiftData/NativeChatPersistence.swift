import ChatPersistenceCore
import Foundation
import SwiftData

public enum NativeChatPersistence {
    private static let schema = Schema([
        Conversation.self,
        Message.self
    ])

    private static let storeNames = [
        "default.store",
        "default.store-shm",
        "default.store-wal"
    ]

    public static func makeSharedContainer(bundleIdentifier: String?) -> ModelContainer {
        createPersistentContainer(bundleIdentifier: bundleIdentifier)
    }

    private static func createPersistentContainer(bundleIdentifier: String?) -> ModelContainer {
        _ = ReleaseResetCoordinator.performIfNeeded(bundleIdentifier: bundleIdentifier)

        do {
            return try makeContainer()
        } catch {}

        _ = preserveExistingStoreForRecovery()

        do {
            return try makeContainer()
        } catch {
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
            assertionFailure("[NativeChatPersistence] Cannot create fallback in-memory ModelContainer: \(error)")
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [configuration])
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
            return nil
        }
    }
}
