import Foundation

/// Performs a one-time data reset when upgrading to a new major release.
///
/// Deletes the persistent store, recovered stores, generated-file caches,
/// temporary previews, user defaults, and the keychain API key. The reset
/// is guarded by a version marker in `UserDefaults` so it only runs once.
public enum ReleaseResetCoordinator {
    /// The release version that triggers the reset.
    public static let targetVersion = "5.0.0"
    /// The `UserDefaults` key used to record that the reset has been completed.
    public static let resetMarkerKey = "release_reset_completed_version"

    private static let persistentStoreFilenames = [
        "default.store",
        "default.store-shm",
        "default.store-wal"
    ]

    private static let recoveredStoreDirectory = ["NativeChat", "RecoveredStores"]
    private static let generatedFileCacheDirectories = ["generated-images", "generated-documents"]
    private static let previewDirectory = ["file_previews"]

    /// Runs the release reset if it has not already been performed for ``targetVersion``.
    ///
    /// - Returns: `true` if the reset was executed, `false` if it was already completed.
    @discardableResult
    public static func performIfNeeded(
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String?,
        applicationSupportDirectory: URL? = nil,
        cachesDirectory: URL? = nil,
        temporaryDirectory: URL? = nil,
        fileManager: FileManager = .default,
        apiKeyReset: ((String) -> Void)? = nil
    ) -> Bool {
        if userDefaults.string(forKey: resetMarkerKey) == targetVersion {
            return false
        }

        let resolvedBundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKeychainService = KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: resolvedBundleIdentifier)

        if let applicationSupportDirectory = resolvedApplicationSupportDirectory(
            explicit: applicationSupportDirectory,
            fileManager: fileManager
        ) {
            deletePersistentStoreFiles(in: applicationSupportDirectory, fileManager: fileManager)
            deleteDirectory(
                pathComponents: recoveredStoreDirectory,
                baseURL: applicationSupportDirectory,
                fileManager: fileManager
            )
        }

        if let cachesDirectory = resolvedCachesDirectory(explicit: cachesDirectory, fileManager: fileManager) {
            for directoryName in generatedFileCacheDirectories {
                deleteDirectory(
                    pathComponents: [directoryName],
                    baseURL: cachesDirectory,
                    fileManager: fileManager
                )
            }
        }

        let temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
        deleteDirectory(
            pathComponents: previewDirectory,
            baseURL: temporaryDirectory,
            fileManager: fileManager
        )

        if let resolvedBundleIdentifier, !resolvedBundleIdentifier.isEmpty {
            userDefaults.removePersistentDomain(forName: resolvedBundleIdentifier)
        }
        userDefaults.set(targetVersion, forKey: resetMarkerKey)

        let reset = apiKeyReset ?? { service in
            KeychainAPIKeyBackend(service: service).deleteAPIKey()
        }
        reset(resolvedKeychainService)

        return true
    }

    private static func resolvedApplicationSupportDirectory(
        explicit: URL?,
        fileManager: FileManager
    ) -> URL? {
        if let explicit {
            return explicit
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static func resolvedCachesDirectory(
        explicit: URL?,
        fileManager: FileManager
    ) -> URL? {
        if let explicit {
            return explicit
        }
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private static func deletePersistentStoreFiles(in applicationSupportDirectory: URL, fileManager: FileManager) {
        for filename in persistentStoreFilenames {
            let fileURL = applicationSupportDirectory.appendingPathComponent(filename)
            removeIfExists(fileURL, fileManager: fileManager)
        }
    }

    private static func deleteDirectory(
        pathComponents: [String],
        baseURL: URL,
        fileManager: FileManager
    ) {
        let targetURL = pathComponents.reduce(baseURL) { partialResult, component in
            partialResult.appendingPathComponent(component, isDirectory: true)
        }
        removeIfExists(targetURL, fileManager: fileManager)
    }

    private static func removeIfExists(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            Loggers.persistence.error("[ReleaseResetCoordinator] Failed to remove \(url.path): \(error.localizedDescription)")
        }
    }
}
