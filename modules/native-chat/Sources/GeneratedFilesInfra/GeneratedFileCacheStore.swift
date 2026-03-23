import Foundation
import GeneratedFilesCore
import os

private let cacheStoreSignposter = OSSignposter(subsystem: "GlassGPT", category: "files")

/// Filesystem-backed cache store for generated files, organized by bucket and cache key.
package struct GeneratedFileCacheStore {
    /// The file manager used for all filesystem operations.
    package let fileManager: FileManager

    /// Optional override for the cache root directory, used for testing.
    let cacheRootOverride: URL?

    /// Creates a cache store using the given file manager.
    package init(fileManager: FileManager = .default, cacheRootOverride: URL? = nil) {
        self.fileManager = fileManager
        self.cacheRootOverride = cacheRootOverride
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
        trimCacheIfNeeded(for: bucket)
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
              isDirectory.boolValue
        else {
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

    /// The default maximum cache size per bucket (200 MB).
    package static let defaultCacheLimitBytes: Int64 = 200 * 1024 * 1024

    /// Evicts the oldest cached entries until the bucket size is within the given limit.
    package func trimCacheIfNeeded(for bucket: GeneratedFileCacheBucket, limitBytes: Int64 = defaultCacheLimitBytes) {
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
}
