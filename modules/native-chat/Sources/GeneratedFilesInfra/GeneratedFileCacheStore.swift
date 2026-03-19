import Foundation
import GeneratedFilesCore
import os

/// Errors originating from cache store filesystem operations.
package enum GeneratedFileStoreError: Error, LocalizedError, Sendable {
    /// The cache root directory could not be created.
    case invalidCacheRoot
    /// A filesystem operation failed with an underlying system error.
    case fileSystemError(underlying: any Error)

    /// A human-readable description of the error.
    package var errorDescription: String? {
        switch self {
        case .invalidCacheRoot:
            return "Unable to create the generated file cache."
        case .fileSystemError(let underlying):
            return "File system operation failed: \(underlying.localizedDescription)"
        }
    }
}

private let cacheStoreSignposter = OSSignposter(subsystem: "GlassGPT", category: "files")

/// Filesystem-backed cache store for generated files, organized by bucket and cache key.
package struct GeneratedFileCacheStore {
    /// Represents a single cached file with its location and metadata.
    package struct CachedEntry {
        /// The parent directory containing this cached file.
        package let directoryURL: URL
        /// The URL of the cached file itself.
        package let fileURL: URL
        /// Size of the cached file in bytes.
        package let size: Int64
        /// Last modification date, used for LRU eviction.
        package let modifiedAt: Date

        /// Creates a cached entry.
        package init(
            directoryURL: URL,
            fileURL: URL,
            size: Int64,
            modifiedAt: Date
        ) {
            self.directoryURL = directoryURL
            self.fileURL = fileURL
            self.size = size
            self.modifiedAt = modifiedAt
        }
    }

    /// The file manager used for all filesystem operations.
    package let fileManager: FileManager

    /// Creates a cache store using the given file manager.
    package init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns the root cache directory URL for the given bucket, optionally creating it.
    package func cacheRootURL(
        for bucket: GeneratedFileCacheBucket,
        createIfNeeded: Bool
    ) -> URL? {
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let rootURL = cachesURL.appendingPathComponent(bucket.directoryName, isDirectory: true)
        if createIfNeeded {
            do {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            } catch {
                GeneratedFilesLogger.error("[cacheRootURL] \(error.localizedDescription)")
                return nil
            }
        }
        return rootURL
    }

    /// Returns the per-key cache directory URL, creating intermediate directories as needed.
    /// - Throws: ``GeneratedFileStoreError/invalidCacheRoot`` if the root cannot be created.
    package func cacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws(GeneratedFileStoreError) -> URL {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: true) else {
            throw GeneratedFileStoreError.invalidCacheRoot
        }

        return rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
    }

    /// Writes file data to the cache, replacing any previous entry for the same key.
    package func storeGeneratedFile(
        data: Data,
        filename: String,
        cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws(GeneratedFileStoreError) -> URL {
        let signpostID = cacheStoreSignposter.makeSignpostID()
        let signpostState = cacheStoreSignposter.beginInterval("StoreGeneratedFile", id: signpostID)
        defer { cacheStoreSignposter.endInterval("StoreGeneratedFile", signpostState) }

        let directoryURL = try cacheDirectoryURL(for: cacheKey, bucket: bucket)
        removeItemIfExists(at: directoryURL, logContext: "storeGeneratedFile.clearDirectory")
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw GeneratedFileStoreError.fileSystemError(underlying: error)
        }

        let fileURL = directoryURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw GeneratedFileStoreError.fileSystemError(underlying: error)
        }
        touchGeneratedFile(at: fileURL)
        return fileURL
    }

    /// Looks up an existing cache entry by key, preferring a file matching the suggested filename.
    package func existingCacheEntry(
        cacheKey: String,
        suggestedFilename: String?,
        bucket: GeneratedFileCacheBucket
    ) -> CachedEntry? {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: false) else {
            return nil
        }

        let directoryURL = rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        if let normalized = normalizedFilename(suggestedFilename, inferredExtension: nil) {
            let preferredURL = directoryURL.appendingPathComponent(normalized)
            if let entry = cachedEntry(fileURL: preferredURL, directoryURL: directoryURL) {
                return entry
            }
        }

        for fileURL in directoryContents(at: directoryURL, logContext: "existingCacheEntry.contents")
        where !isDirectoryURL(fileURL) {
            if let entry = cachedEntry(fileURL: fileURL, directoryURL: directoryURL) {
                return entry
            }
        }

        return nil
    }

    /// Returns all cached entries for the given bucket.
    package func cacheEntries(for bucket: GeneratedFileCacheBucket) -> [CachedEntry] {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: false) else {
            return []
        }

        return directoryContents(at: rootURL, logContext: "cacheEntries.rootContents").compactMap { directoryURL in
            guard isDirectoryURL(directoryURL) else {
                return nil
            }

            for fileURL in directoryContents(at: directoryURL, logContext: "cacheEntries.directoryContents")
            where !isDirectoryURL(fileURL) {
                if let entry = cachedEntry(fileURL: fileURL, directoryURL: directoryURL) {
                    return entry
                }
            }

            return nil
        }
    }

    /// Returns the total size in bytes of all cached files in the given bucket.
    package func cacheSize(for bucket: GeneratedFileCacheBucket) -> Int64 {
        cacheEntries(for: bucket).reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }
    }

    /// Evicts the oldest cached entries until the bucket size is within the given limit.
    package func trimCacheIfNeeded(for bucket: GeneratedFileCacheBucket, limitBytes: Int64) {
        let entries = cacheEntries(for: bucket)
            .sorted { $0.modifiedAt < $1.modifiedAt }

        var runningSize = entries.reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }

        guard runningSize > limitBytes else { return }

        for entry in entries where runningSize > limitBytes {
            removeItemIfExists(at: entry.directoryURL, logContext: "trimCacheIfNeeded")
            runningSize -= entry.size
        }
    }

    /// Updates the modification date of a cache entry to mark it as recently used.
    package func touchCacheEntry(_ entry: CachedEntry) {
        touchGeneratedFile(at: entry.fileURL)
    }

    /// Updates the modification date of the file at the given URL to the current time.
    package func touchGeneratedFile(at fileURL: URL) {
        setItemModificationDate(Date(), atPath: fileURL.path, logContext: "touchGeneratedFile")
    }

    /// Deletes the entire cache directory for the given bucket.
    package func clearCache(for bucket: GeneratedFileCacheBucket) {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: false) else {
            return
        }

        removeItemIfExists(at: rootURL, logContext: "clearCache")
    }

    /// Removes the temporary file previews directory.
    package func cleanupTempPreviews() {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("file_previews", isDirectory: true)
        removeItemIfExists(at: tempDir, logContext: "cleanupTempPreviews")
    }

    /// Replaces path-unsafe characters in a cache key with underscores.
    package func sanitizedCacheKey(_ cacheKey: String) -> String {
        cacheKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    /// Returns `true` if the URL points to an existing directory.
    package func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
