import ChatPersistenceCore
import Foundation
import os
import SwiftData

/// Result of bootstrapping the persistent store, including the container and any recovery status.
public struct NativeChatPersistenceBootstrap {
    /// The SwiftData model container, or `nil` if all creation attempts failed.
    public let container: ModelContainer?
    /// `true` if the store was recovered from a corrupted state during bootstrap.
    public let didRecoverPersistentStore: Bool
    /// A user-facing error description if the store could not be created.
    public let startupErrorDescription: String?

    /// Creates a bootstrap result.
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

/// Factory that creates and configures the SwiftData `ModelContainer` for chat persistence.
///
/// On first failure the existing store is preserved for recovery and a fresh container
/// is attempted. If that also fails an in-memory fallback is used.
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

    /// Creates a ``NativeChatPersistenceBootstrap`` with the full recovery pipeline.
    public static func makeSharedBootstrap(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        createPersistentContainer(bundleIdentifier: bundleIdentifier)
    }

    /// Convenience that returns only the `ModelContainer` from the bootstrap result.
    public static func makeSharedContainer(bundleIdentifier: String?) -> ModelContainer? {
        makeSharedBootstrap(bundleIdentifier: bundleIdentifier).container
    }

    private static let persistenceSignposter = OSSignposter(subsystem: "GlassGPT", category: "persistence")

    private static func createPersistentContainer(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        let signpostID = persistenceSignposter.makeSignpostID()
        let signpostState = persistenceSignposter.beginInterval("CreatePersistentContainer", id: signpostID)
        defer { persistenceSignposter.endInterval("CreatePersistentContainer", signpostState) }

        _ = ReleaseResetCoordinator.performIfNeeded(bundleIdentifier: bundleIdentifier)

        do {
            return try NativeChatPersistenceBootstrap(
                container: makeContainer(),
                didRecoverPersistentStore: false,
                startupErrorDescription: nil
            )
        } catch {
            Loggers.persistence.error("[NativeChatPersistence] Initial persistent container creation failed: \(error.localizedDescription)")
        }

        let preservationResult = preserveExistingStoreForRecovery()
        if case let .failed(message) = preservationResult {
            Loggers.persistence.error("[NativeChatPersistence] \(message)")
        }

        do {
            return try NativeChatPersistenceBootstrap(
                container: makeContainer(),
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
            // swiftlint:disable:next line_length
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
