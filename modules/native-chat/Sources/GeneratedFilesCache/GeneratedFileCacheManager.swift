import Foundation
import GeneratedFilesCore

/// Actor responsible for generated-file cache inspection and clearing without provider transport dependencies.
public actor GeneratedFileCacheManager {
    public static let generatedImageCacheLimitBytes: Int64 = 250 * 1024 * 1024
    public static let generatedDocumentCacheLimitBytes: Int64 = 250 * 1024 * 1024
    public static let memoryPressureTrimRatio = 0.5

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

    public func cachedGeneratedFile(for descriptor: GeneratedFileDescriptor) -> GeneratedFileLocalResource? {
        let preferredBucket = GeneratedFilePolicy.cacheBucket(for: descriptor)
        let bucketsToSearch: [GeneratedFileCacheBucket] = preferredBucket == .image
            ? [.image, .document]
            : [.document, .image]
        let cacheKey = GeneratedFilePolicy.cacheKey(for: descriptor).identity

        for bucket in bucketsToSearch {
            guard let entry = cacheStore.existingCacheEntry(
                cacheKey: cacheKey,
                suggestedFilename: descriptor.filename,
                bucket: bucket
            ) else {
                continue
            }

            cacheStore.touchCacheEntry(entry)
            let resolvedDescriptor = GeneratedFileDescriptor(
                fileID: descriptor.fileID,
                containerID: descriptor.containerID,
                filename: entry.fileURL.lastPathComponent,
                mediaType: descriptor.mediaType
            )
            return GeneratedFileLocalResource(
                localURL: entry.fileURL,
                filename: entry.fileURL.lastPathComponent,
                cacheBucket: bucket,
                openBehavior: GeneratedFilePolicy.openBehavior(for: resolvedDescriptor)
            )
        }

        return nil
    }

    public func storeGeneratedFile(
        data: Data,
        descriptor: GeneratedFileDescriptor
    ) throws -> GeneratedFileLocalResource {
        let resolvedFilename = GeneratedFilePolicy.resolvedFilename(for: descriptor)
        let resolvedDescriptor = GeneratedFileDescriptor(
            fileID: descriptor.fileID,
            containerID: descriptor.containerID,
            filename: resolvedFilename,
            mediaType: descriptor.mediaType
        )
        let cacheKey = GeneratedFilePolicy.cacheKey(for: resolvedDescriptor)
        let fileURL = try cacheStore.storeGeneratedFile(
            data: data,
            filename: resolvedFilename,
            cacheKey: cacheKey.identity,
            bucket: cacheKey.bucket
        )
        return GeneratedFileLocalResource(
            localURL: fileURL,
            filename: resolvedFilename,
            cacheBucket: cacheKey.bucket,
            openBehavior: GeneratedFilePolicy.openBehavior(for: resolvedDescriptor)
        )
    }

    /// Trims both generated-file cache buckets to tighter limits when iOS reports memory pressure.
    public func trimCachesForMemoryPressure() {
        trimCachesForMemoryPressure(
            imageLimitBytes: Self.memoryPressureGeneratedImageCacheLimitBytes,
            documentLimitBytes: Self.memoryPressureGeneratedDocumentCacheLimitBytes
        )
    }

    package static var memoryPressureGeneratedImageCacheLimitBytes: Int64 {
        Int64(Double(generatedImageCacheLimitBytes) * memoryPressureTrimRatio)
    }

    package static var memoryPressureGeneratedDocumentCacheLimitBytes: Int64 {
        Int64(Double(generatedDocumentCacheLimitBytes) * memoryPressureTrimRatio)
    }

    package func trimCachesForMemoryPressure(
        imageLimitBytes: Int64,
        documentLimitBytes: Int64
    ) {
        cacheStore.trimCacheIfNeeded(for: .image, limitBytes: imageLimitBytes)
        cacheStore.trimCacheIfNeeded(for: .document, limitBytes: documentLimitBytes)
    }
}
