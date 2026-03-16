import Foundation

extension FileDownloadService {
    func generatedCacheRootURL(
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
                Loggers.files.error("[generatedCacheRootURL] \(error.localizedDescription)")
                return nil
            }
        }
        return rootURL
    }

    func generatedCacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        guard let rootURL = generatedCacheRootURL(for: bucket, createIfNeeded: true) else {
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
        let directoryURL = try generatedCacheDirectoryURL(for: cacheKey, bucket: bucket)
        removeItemIfExists(at: directoryURL, logContext: "storeGeneratedFile.clearDirectory")
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        touchGeneratedFile(at: fileURL)
        return fileURL
    }

    func existingGeneratedFileCacheEntry(
        cacheKey: String,
        suggestedFilename: String?,
        bucket: GeneratedFileCacheBucket
    ) -> CachedGeneratedFileEntry? {
        guard let rootURL = generatedCacheRootURL(for: bucket, createIfNeeded: false) else {
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
            if let entry = cachedGeneratedFileEntry(fileURL: preferredURL, directoryURL: directoryURL) {
                return entry
            }
        }

        for fileURL in directoryContents(at: directoryURL, logContext: "existingGeneratedFileCacheEntry.contents")
        where !isDirectoryURL(fileURL) {
            if let entry = cachedGeneratedFileEntry(fileURL: fileURL, directoryURL: directoryURL) {
                return entry
            }
        }

        return nil
    }

    func cachedGeneratedFileEntry(
        fileURL: URL,
        directoryURL: URL
    ) -> CachedGeneratedFileEntry? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let attributes = itemAttributes(atPath: fileURL.path, logContext: "cachedGeneratedFileEntry.attributes"),
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }

        return CachedGeneratedFileEntry(
            directoryURL: directoryURL,
            fileURL: fileURL,
            size: fileSize.int64Value,
            modifiedAt: (attributes[.modificationDate] as? Date) ?? .distantPast
        )
    }

    func generatedFileCacheEntries(for bucket: GeneratedFileCacheBucket) -> [CachedGeneratedFileEntry] {
        guard let rootURL = generatedCacheRootURL(for: bucket, createIfNeeded: false) else {
            return []
        }

        return directoryContents(at: rootURL, logContext: "generatedFileCacheEntries.rootContents").compactMap { directoryURL in
            guard isDirectoryURL(directoryURL) else {
                return nil
            }

            for fileURL in directoryContents(at: directoryURL, logContext: "generatedFileCacheEntries.directoryContents")
            where !isDirectoryURL(fileURL) {
                if let entry = cachedGeneratedFileEntry(fileURL: fileURL, directoryURL: directoryURL) {
                    return entry
                }
            }

            return nil
        }
    }

    func generatedFileCacheSize(for bucket: GeneratedFileCacheBucket) -> Int64 {
        generatedFileCacheEntries(for: bucket).reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }
    }

    func trimGeneratedFileCacheIfNeeded(for bucket: GeneratedFileCacheBucket) {
        var entries = generatedFileCacheEntries(for: bucket).sorted { lhs, rhs in
            lhs.modifiedAt < rhs.modifiedAt
        }

        let limit: Int64
        switch bucket {
        case .image:
            limit = Self.generatedImageCacheLimitBytes
        case .document:
            limit = Self.generatedDocumentCacheLimitBytes
        }

        var totalSize = entries.reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }

        while totalSize > limit, entries.count > 1 {
            let entry = entries.removeFirst()
            totalSize -= entry.size
            removeItemIfExists(at: entry.directoryURL, logContext: "trimGeneratedFileCacheIfNeeded.removeOldest")
        }
    }

    func touchGeneratedFileCacheEntry(_ entry: CachedGeneratedFileEntry) {
        touchGeneratedFile(at: entry.fileURL)
    }

    func touchGeneratedFile(at fileURL: URL) {
        let now = Date()
        setItemModificationDate(now, atPath: fileURL.path, logContext: "touchGeneratedFile.file")
        setItemModificationDate(now, atPath: fileURL.deletingLastPathComponent().path, logContext: "touchGeneratedFile.directory")
    }

    func clearGeneratedFileCache(for bucket: GeneratedFileCacheBucket) {
        guard let cacheRoot = generatedCacheRootURL(for: bucket, createIfNeeded: false) else {
            return
        }

        removeItemIfExists(at: cacheRoot, logContext: "clearGeneratedFileCache")
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

    func cleanupCache() {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("file_previews", isDirectory: true)
        removeItemIfExists(at: tempDir, logContext: "cleanupCache")
    }

    func removeItemIfExists(at url: URL, logContext: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
        }
    }

    func directoryContents(at url: URL, logContext: String) -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
            return []
        }
    }

    func itemAttributes(atPath path: String, logContext: String) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
            return nil
        }
    }

    func setItemModificationDate(_ date: Date, atPath path: String, logContext: String) {
        do {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: path)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
        }
    }
}
