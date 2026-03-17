import Foundation

/// Lightweight helper that owns all generated-file cache filesystem operations.
package struct GeneratedFileCacheStore {
    package struct CachedEntry {
        package let directoryURL: URL
        package let fileURL: URL
        package let size: Int64
        package let modifiedAt: Date

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

    package let fileManager: FileManager

    package init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

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

    package func cacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: true) else {
            throw GeneratedFileStoreError.invalidCacheRoot
        }

        return rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
    }

    package func storeGeneratedFile(
        data: Data,
        filename: String,
        cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        let directoryURL = try cacheDirectoryURL(for: cacheKey, bucket: bucket)
        removeItemIfExists(at: directoryURL, logContext: "storeGeneratedFile.clearDirectory")
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        touchGeneratedFile(at: fileURL)
        return fileURL
    }

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

    package func cacheSize(for bucket: GeneratedFileCacheBucket) -> Int64 {
        cacheEntries(for: bucket).reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }
    }

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

    package func touchCacheEntry(_ entry: CachedEntry) {
        touchGeneratedFile(at: entry.fileURL)
    }

    package func touchGeneratedFile(at fileURL: URL) {
        setItemModificationDate(Date(), atPath: fileURL.path, logContext: "touchGeneratedFile")
    }

    package func clearCache(for bucket: GeneratedFileCacheBucket) {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: false) else {
            return
        }

        removeItemIfExists(at: rootURL, logContext: "clearCache")
    }

    package func cleanupTempPreviews() {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("file_previews", isDirectory: true)
        removeItemIfExists(at: tempDir, logContext: "cleanupTempPreviews")
    }

    package func sanitizedCacheKey(_ cacheKey: String) -> String {
        cacheKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    package func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
