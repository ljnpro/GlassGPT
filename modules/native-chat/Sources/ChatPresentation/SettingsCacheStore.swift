import Foundation
import GeneratedFilesCache
import Observation

/// Observable generated-file cache state for the settings scene.
@Observable
@MainActor
public final class SettingsCacheStore {
    /// Current size in bytes of the generated image cache.
    public var generatedImageCacheSizeBytes: Int64 = 0
    /// Current size in bytes of the generated document cache.
    public var generatedDocumentCacheSizeBytes: Int64 = 0
    /// Whether the image cache is currently being cleared.
    public var isClearingImageCache = false
    /// Whether the document cache is currently being cleared.
    public var isClearingDocumentCache = false
    /// Human-readable string for the image cache size limit.
    public let generatedImageCacheLimitString: String
    /// Human-readable string for the document cache size limit.
    public let generatedDocumentCacheLimitString: String

    private let cacheManager: GeneratedFileCacheManager

    /// Human-readable string for the current image cache size.
    public var generatedImageCacheSizeString: String {
        SettingsPresenter.byteCountFormatter.string(
            fromByteCount: generatedImageCacheSizeBytes
        )
    }

    /// Human-readable string for the current document cache size.
    public var generatedDocumentCacheSizeString: String {
        SettingsPresenter.byteCountFormatter.string(
            fromByteCount: generatedDocumentCacheSizeBytes
        )
    }

    /// Creates cache state for the settings scene.
    public init(
        generatedImageCacheLimitString: String,
        generatedDocumentCacheLimitString: String,
        cacheManager: GeneratedFileCacheManager
    ) {
        self.generatedImageCacheLimitString = generatedImageCacheLimitString
        self.generatedDocumentCacheLimitString = generatedDocumentCacheLimitString
        self.cacheManager = cacheManager
    }

    /// Refreshes both generated-file cache sizes.
    public func refreshAll() async {
        await applySnapshot()
    }

    /// Refreshes the generated image cache size display.
    public func refreshGeneratedImageCacheSize() async {
        await applySnapshot()
    }

    /// Refreshes the generated document cache size display.
    public func refreshGeneratedDocumentCacheSize() async {
        await applySnapshot()
    }

    /// Clears the generated image cache and updates the displayed sizes.
    public func clearGeneratedImageCache() async {
        guard !isClearingImageCache else { return }
        isClearingImageCache = true
        await cacheManager.clearGeneratedImageCache()
        await applySnapshot()
        isClearingImageCache = false
    }

    /// Clears the generated document cache and updates the displayed sizes.
    public func clearGeneratedDocumentCache() async {
        guard !isClearingDocumentCache else { return }
        isClearingDocumentCache = true
        await cacheManager.clearGeneratedDocumentCache()
        await applySnapshot()
        isClearingDocumentCache = false
    }

    private func applySnapshot() async {
        generatedImageCacheSizeBytes = await cacheManager.generatedImageCacheSize()
        generatedDocumentCacheSizeBytes = await cacheManager.generatedDocumentCacheSize()
    }
}
