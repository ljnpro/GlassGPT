import ChatApplication
import Foundation
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

    private let controller: SettingsSceneController

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
        controller: SettingsSceneController
    ) {
        self.generatedImageCacheLimitString = generatedImageCacheLimitString
        self.generatedDocumentCacheLimitString = generatedDocumentCacheLimitString
        self.controller = controller
    }

    /// Refreshes both generated-file cache sizes.
    public func refreshAll() async {
        await apply(controller.refreshGeneratedCacheSnapshot())
    }

    /// Refreshes the generated image cache size display.
    public func refreshGeneratedImageCacheSize() async {
        await apply(controller.refreshGeneratedCacheSnapshot())
    }

    /// Refreshes the generated document cache size display.
    public func refreshGeneratedDocumentCacheSize() async {
        await apply(controller.refreshGeneratedCacheSnapshot())
    }

    /// Clears the generated image cache and updates the displayed sizes.
    public func clearGeneratedImageCache() async {
        guard !isClearingImageCache else { return }
        isClearingImageCache = true
        await apply(controller.clearGeneratedCache(.image))
        isClearingImageCache = false
    }

    /// Clears the generated document cache and updates the displayed sizes.
    public func clearGeneratedDocumentCache() async {
        guard !isClearingDocumentCache else { return }
        isClearingDocumentCache = true
        await apply(controller.clearGeneratedCache(.document))
        isClearingDocumentCache = false
    }

    private func apply(_ snapshot: SettingsCacheSnapshot) {
        generatedImageCacheSizeBytes = snapshot.imageBytes
        generatedDocumentCacheSizeBytes = snapshot.documentBytes
    }
}
