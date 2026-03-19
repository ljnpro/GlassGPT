import Foundation
import GeneratedFilesCore
import OpenAITransport

/// Actor responsible for downloading files from OpenAI.
public actor FileDownloadService {
    /// Maximum size in bytes for the generated image cache (250 MB).
    public static let generatedImageCacheLimitBytes: Int64 = 250 * 1024 * 1024
    /// Maximum size in bytes for the generated document cache (250 MB).
    public static let generatedDocumentCacheLimitBytes: Int64 = 250 * 1024 * 1024

    struct GeneratedFilePayload {
        let data: Data
        let filename: String
        let cacheBucket: GeneratedFileCacheBucket
        let openBehavior: GeneratedFileOpenBehavior
    }

    var inFlightDownloads: [String: Task<URL, Error>] = [:]
    var inFlightGeneratedFileDownloads: [String: Task<GeneratedFileLocalResource, Error>] = [:]
    let configurationProvider: OpenAIConfigurationProvider
    let requestAuthorizer: OpenAIRequestAuthorizer
    nonisolated let transport: OpenAIDataTransport
    let fileManager: FileManager
    let cacheStore: GeneratedFileCacheStore
    let namingResolver: GeneratedFileNamingResolver
    let downloadClient: GeneratedFileDownloadClient

    /// Creates a download service with the given configuration and optional overrides.
    public init(
        configurationProvider: OpenAIConfigurationProvider,
        requestAuthorizer: OpenAIRequestAuthorizer? = nil,
        transport: OpenAIDataTransport? = nil,
        fileManager: FileManager = .default
    ) {
        let authorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(configuration: configurationProvider)
        let resolvedTransport = transport ?? OpenAIURLSessionTransport(
            session: OpenAITransportSessionFactory.makeDownloadSession()
        )
        let resolvedNamingResolver = GeneratedFileNamingResolver()
        self.configurationProvider = configurationProvider
        self.requestAuthorizer = authorizer
        self.transport = resolvedTransport
        self.fileManager = fileManager
        self.cacheStore = GeneratedFileCacheStore(fileManager: fileManager)
        self.namingResolver = resolvedNamingResolver
        self.downloadClient = GeneratedFileDownloadClient(
            configurationProvider: configurationProvider,
            requestAuthorizer: authorizer,
            transport: resolvedTransport,
            namingResolver: resolvedNamingResolver
        )
    }

    /// Downloads a file to a temporary directory, deduplicating concurrent requests for the same key.
    public func downloadFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws(any Error) -> URL {
        let key = namingResolver.downloadKey(fileId: fileId, containerId: containerId)

        if let existingTask = inFlightDownloads[key] {
            return try await existingTask.value
        }

        let task = Task<URL, Error> {
            defer { inFlightDownloads[key] = nil }
            return try await performDownload(
                fileId: fileId,
                containerId: containerId,
                suggestedFilename: suggestedFilename,
                apiKey: apiKey
            )
        }

        inFlightDownloads[key] = task
        return try await task.value
    }

    /// Downloads and caches a generated file, returning a local resource. Returns a cached copy if available.
    public func prefetchGeneratedFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws(any Error) -> GeneratedFileLocalResource {
        let key = namingResolver.downloadKey(fileId: fileId, containerId: containerId)

        if let cached = cachedGeneratedFile(
            fileId: fileId,
            containerId: containerId,
            suggestedFilename: suggestedFilename
        ) {
            return cached
        }

        if let existingTask = inFlightGeneratedFileDownloads[key] {
            return try await existingTask.value
        }

        let task = Task<GeneratedFileLocalResource, Error> {
            defer { inFlightGeneratedFileDownloads[key] = nil }
            return try await performGeneratedFilePrefetch(
                fileId: fileId,
                containerId: containerId,
                suggestedFilename: suggestedFilename,
                apiKey: apiKey
            )
        }

        inFlightGeneratedFileDownloads[key] = task
        return try await task.value
    }

    /// Returns a previously cached generated file resource, or `nil` if not cached.
    public func cachedGeneratedFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?
    ) -> GeneratedFileLocalResource? {
        let key = namingResolver.downloadKey(fileId: fileId, containerId: containerId)
        let preferredBucket = GeneratedFileCachePolicy.cacheBucket(for: suggestedFilename)
        let bucketsToSearch: [GeneratedFileCacheBucket] = preferredBucket == .image
            ? [.image, .document]
            : [.document, .image]

        for bucket in bucketsToSearch {
            guard let entry = existingGeneratedFileCacheEntry(
                cacheKey: key,
                suggestedFilename: suggestedFilename,
                bucket: bucket
            ) else {
                continue
            }

            touchGeneratedFileCacheEntry(entry)
            let filename = entry.fileURL.lastPathComponent
            return GeneratedFileLocalResource(
                localURL: entry.fileURL,
                filename: filename,
                cacheBucket: bucket,
                openBehavior: GeneratedFileCachePolicy.openBehavior(for: filename)
            )
        }

        return nil
    }

    /// Returns the current size in bytes of the generated image cache.
    public func generatedImageCacheSize() -> Int64 {
        generatedFileCacheSize(for: .image)
    }

    /// Removes all cached generated images.
    public func clearGeneratedImageCache() {
        clearGeneratedFileCache(for: .image)
    }

    /// Returns the current size in bytes of the generated document cache.
    public func generatedDocumentCacheSize() -> Int64 {
        generatedFileCacheSize(for: .document)
    }

    /// Removes all cached generated documents.
    public func clearGeneratedDocumentCache() {
        clearGeneratedFileCache(for: .document)
    }

    /// Returns the open behavior for a given filename based on its extension.
    public static func openBehavior(for filename: String?) -> GeneratedFileOpenBehavior {
        GeneratedFileCachePolicy.openBehavior(for: filename)
    }

    /// Cancels an in-flight prefetch for the specified file.
    public func cancelGeneratedFilePrefetch(fileId: String, containerId: String?) {
        let key = namingResolver.downloadKey(fileId: fileId, containerId: containerId)
        inFlightGeneratedFileDownloads.removeValue(forKey: key)?.cancel()
    }

    /// Cancels all in-flight generated file prefetch tasks.
    public func cancelAllGeneratedFilePrefetches() {
        for task in inFlightGeneratedFileDownloads.values {
            task.cancel()
        }
        inFlightGeneratedFileDownloads.removeAll()
    }
}
