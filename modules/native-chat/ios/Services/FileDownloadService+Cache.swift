import Foundation

extension FileDownloadService {
    func generatedCacheRootURL(
        for bucket: GeneratedFileCacheBucket,
        createIfNeeded: Bool
    ) -> URL? {
        cacheStore.cacheRootURL(for: bucket, createIfNeeded: createIfNeeded)
    }

    func generatedCacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        try cacheStore.cacheDirectoryURL(for: cacheKey, bucket: bucket)
    }

    func storeGeneratedFile(
        data: Data,
        filename: String,
        cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        try cacheStore.storeGeneratedFile(
            data: data,
            filename: filename,
            cacheKey: cacheKey,
            bucket: bucket
        )
    }

    func existingGeneratedFileCacheEntry(
        cacheKey: String,
        suggestedFilename: String?,
        bucket: GeneratedFileCacheBucket
    ) -> CachedGeneratedFileEntry? {
        cacheStore.existingCacheEntry(
            cacheKey: cacheKey,
            suggestedFilename: suggestedFilename,
            bucket: bucket
        )
    }

    func generatedFileCacheEntries(for bucket: GeneratedFileCacheBucket) -> [CachedGeneratedFileEntry] {
        cacheStore.cacheEntries(for: bucket)
    }

    func generatedFileCacheSize(for bucket: GeneratedFileCacheBucket) -> Int64 {
        cacheStore.cacheSize(for: bucket)
    }

    func trimGeneratedFileCacheIfNeeded(for bucket: GeneratedFileCacheBucket) {
        let limit: Int64 = switch bucket {
        case .image: Self.generatedImageCacheLimitBytes
        case .document: Self.generatedDocumentCacheLimitBytes
        }
        cacheStore.trimCacheIfNeeded(for: bucket, limitBytes: limit)
    }

    func touchGeneratedFileCacheEntry(_ entry: CachedGeneratedFileEntry) {
        cacheStore.touchCacheEntry(entry)
    }

    func touchGeneratedFile(at fileURL: URL) {
        cacheStore.touchGeneratedFile(at: fileURL)
    }

    func clearGeneratedFileCache(for bucket: GeneratedFileCacheBucket) {
        cacheStore.clearCache(for: bucket)
    }

    func sanitizedCacheKey(_ cacheKey: String) -> String {
        cacheStore.sanitizedCacheKey(cacheKey)
    }

    func isDirectoryURL(_ url: URL) -> Bool {
        cacheStore.isDirectoryURL(url)
    }

    func cleanupCache() {
        cacheStore.cleanupTempPreviews()
    }

    func removeItemIfExists(at url: URL, logContext: String) {
        cacheStore.removeItemIfExists(at: url, logContext: logContext)
    }

    func directoryContents(at url: URL, logContext: String) -> [URL] {
        cacheStore.directoryContents(at: url, logContext: logContext)
    }

    func itemAttributes(atPath path: String, logContext: String) -> [FileAttributeKey: Any]? {
        cacheStore.itemAttributes(atPath: path, logContext: logContext)
    }

    func setItemModificationDate(_ date: Date, atPath path: String, logContext: String) {
        cacheStore.setItemModificationDate(date, atPath: path, logContext: logContext)
    }
}
