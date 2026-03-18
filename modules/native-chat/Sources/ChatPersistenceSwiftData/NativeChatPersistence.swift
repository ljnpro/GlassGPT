import ChatPersistenceCore
import Foundation
import SwiftData

public struct NativeChatPersistenceBootstrap {
    public let container: ModelContainer?
    public let didRecoverPersistentStore: Bool
    public let startupErrorDescription: String?

    public init(
        container: ModelContainer?,
        didRecoverPersistentStore: Bool,
        startupErrorDescription: String?
    ) {
        self.container = container
        self.didRecoverPersistentStore = didRecoverPersistentStore
        self.startupErrorDescription = startupErrorDescription
    }
}

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

    private enum StoreRecoveryPreservationResult {
        case noExistingStore
        case preserved(URL)
        case failed(String)

        var didRecoverPersistentStore: Bool {
            if case .preserved = self {
                return true
            }
            return false
        }
    }

    public static func makeSharedBootstrap(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        createPersistentContainer(bundleIdentifier: bundleIdentifier)
    }

    public static func makeSharedContainer(bundleIdentifier: String?) -> ModelContainer? {
        makeSharedBootstrap(bundleIdentifier: bundleIdentifier).container
    }

    private static func createPersistentContainer(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        _ = ReleaseResetCoordinator.performIfNeeded(bundleIdentifier: bundleIdentifier)

        do {
            return NativeChatPersistenceBootstrap(
                container: try makeContainer(),
                didRecoverPersistentStore: false,
                startupErrorDescription: nil
            )
        } catch {
            Loggers.persistence.error("[NativeChatPersistence] Initial persistent container creation failed: \(error.localizedDescription)")
        }

        let preservationResult = preserveExistingStoreForRecovery()
        if case .failed(let message) = preservationResult {
            Loggers.persistence.error("[NativeChatPersistence] \(message)")
        }

        do {
            return NativeChatPersistenceBootstrap(
                container: try makeContainer(),
                didRecoverPersistentStore: preservationResult.didRecoverPersistentStore,
                startupErrorDescription: nil
            )
        } catch {
            Loggers.persistence.error("[NativeChatPersistence] Persistent container retry failed: \(error.localizedDescription)")
        }

        if let inMemoryContainer = makeInMemoryContainer() {
            return NativeChatPersistenceBootstrap(
                container: inMemoryContainer,
                didRecoverPersistentStore: preservationResult.didRecoverPersistentStore,
                startupErrorDescription: nil
            )
        }

        let userFacingError = "Failed to initialize local chat storage. Restart the app and try again."
        Loggers.persistence.error("[NativeChatPersistence] In-memory fallback failed. Storage is unavailable.")
        return NativeChatPersistenceBootstrap(
            container: nil,
            didRecoverPersistentStore: preservationResult.didRecoverPersistentStore,
            startupErrorDescription: userFacingError
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeInMemoryContainer() -> ModelContainer? {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Loggers.persistence.error("[NativeChatPersistence] Cannot create fallback in-memory ModelContainer: \(error.localizedDescription)")
            return nil
        }
    }

    private static func preserveExistingStoreForRecovery() -> StoreRecoveryPreservationResult {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return .failed("Application Support directory is unavailable for store recovery.")
        }

        let existingStoreURLs = storeNames
            .map { appSupportURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        guard !existingStoreURLs.isEmpty else {
            return .noExistingStore
        }

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

            return .preserved(recoveryDirectory)
        } catch {
            return .failed("Failed to preserve existing store for recovery: \(error.localizedDescription)")
        }
    }
}
