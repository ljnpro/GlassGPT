import Foundation

/// Actor responsible for generated-file cache inspection and clearing without provider transport dependencies.
public actor GeneratedFileCacheManager {
    public static let generatedImageCacheLimitBytes: Int64 = 250 * 1024 * 1024
    public static let generatedDocumentCacheLimitBytes: Int64 = 250 * 1024 * 1024

    private let cacheStore: GeneratedFileCacheStore

    public init(
        fileManager: FileManager = .default,
        cacheRootOverride: URL? = nil
    ) {
        cacheStore = GeneratedFileCacheStore(
            fileManager: fileManager,
            cacheRootOverride: cacheRootOverride
        )
    }

    public func generatedImageCacheSize() -> Int64 {
        cacheStore.cacheSize(for: .image)
    }

    public func generatedDocumentCacheSize() -> Int64 {
        cacheStore.cacheSize(for: .document)
    }

    public func clearGeneratedImageCache() {
        cacheStore.clearCache(for: .image)
    }

    public func clearGeneratedDocumentCache() {
        cacheStore.clearCache(for: .document)
    }
}
