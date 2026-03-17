import Foundation

/// Lightweight helper that owns all generated-file cache filesystem operations.
struct GeneratedFileCacheStore {
    struct CachedEntry {
        let directoryURL: URL
        let fileURL: URL
        let size: Int64
        let modifiedAt: Date
    }

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func cacheRootURL(
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
                Loggers.files.error("[cacheRootURL] \(error.localizedDescription)")
                return nil
            }
        }
        return rootURL
    }

    func cacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: true) else {
            throw FileDownloadError.invalidURL
        }

        return rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
    }

    func storeGeneratedFile(
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

    func existingCacheEntry(
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

    func cacheEntries(for bucket: GeneratedFileCacheBucket) -> [CachedEntry] {
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

    func cacheSize(for bucket: GeneratedFileCacheBucket) -> Int64 {
        cacheEntries(for: bucket).reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }
    }

    func trimCacheIfNeeded(for bucket: GeneratedFileCacheBucket, limitBytes: Int64) {
        var entries = cacheEntries(for: bucket).sorted { lhs, rhs in
            lhs.modifiedAt < rhs.modifiedAt
        }

        var totalSize = entries.reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }

        while totalSize > limitBytes, entries.count > 1 {
            let entry = entries.removeFirst()
            totalSize -= entry.size
            removeItemIfExists(at: entry.directoryURL, logContext: "trimCacheIfNeeded.removeOldest")
        }
    }

    func touchCacheEntry(_ entry: CachedEntry) {
        touchGeneratedFile(at: entry.fileURL)
    }

    func touchGeneratedFile(at fileURL: URL) {
        let now = Date()
        setItemModificationDate(now, atPath: fileURL.path, logContext: "touchGeneratedFile.file")
        setItemModificationDate(now, atPath: fileURL.deletingLastPathComponent().path, logContext: "touchGeneratedFile.directory")
    }

    func clearCache(for bucket: GeneratedFileCacheBucket) {
        guard let cacheRoot = cacheRootURL(for: bucket, createIfNeeded: false) else {
            return
        }

        removeItemIfExists(at: cacheRoot, logContext: "clearCache")
    }

    func cleanupTempPreviews() {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("file_previews", isDirectory: true)
        removeItemIfExists(at: tempDir, logContext: "cleanupCache")
    }

    func sanitizedCacheKey(_ cacheKey: String) -> String {
        cacheKey.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
    }

    func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}
