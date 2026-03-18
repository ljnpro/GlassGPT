import Foundation
import GeneratedFilesCore
import OpenAITransport

/// Actor responsible for downloading files from OpenAI.
public actor FileDownloadService {
    public static let generatedImageCacheLimitBytes: Int64 = 250 * 1024 * 1024
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

    public init(
        configurationProvider: OpenAIConfigurationProvider,
        requestAuthorizer: OpenAIRequestAuthorizer? = nil,
        transport: OpenAIDataTransport? = nil,
        fileManager: FileManager = .default
    ) {
        let authorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(configuration: configurationProvider)
        let resolvedTransport = transport ?? OpenAIURLSessionTransport(session: Self.makeDownloadSession())
        self.configurationProvider = configurationProvider
        self.requestAuthorizer = authorizer
        self.transport = resolvedTransport
        self.fileManager = fileManager
        self.cacheStore = GeneratedFileCacheStore(fileManager: fileManager)
    }

    private static func makeDownloadSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    public func downloadFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> URL {
        let key = downloadKey(fileId: fileId, containerId: containerId)

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

    public func prefetchGeneratedFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> GeneratedFileLocalResource {
        let key = downloadKey(fileId: fileId, containerId: containerId)

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

    public func cachedGeneratedFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?
    ) -> GeneratedFileLocalResource? {
        let key = downloadKey(fileId: fileId, containerId: containerId)
        let preferredBucket = Self.cacheBucket(for: suggestedFilename)
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
                openBehavior: Self.openBehavior(for: filename)
            )
        }

        return nil
    }

    public func generatedImageCacheSize() -> Int64 {
        generatedFileCacheSize(for: .image)
    }

    public func clearGeneratedImageCache() {
        clearGeneratedFileCache(for: .image)
    }

    public func generatedDocumentCacheSize() -> Int64 {
        generatedFileCacheSize(for: .document)
    }

    public func clearGeneratedDocumentCache() {
        clearGeneratedFileCache(for: .document)
    }
}
