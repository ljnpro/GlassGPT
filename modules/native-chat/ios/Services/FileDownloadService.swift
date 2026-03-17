import Foundation

enum GeneratedFileCacheBucket: String, Sendable {
    case image
    case document

    var directoryName: String {
        switch self {
        case .image:
            return "generated-images"
        case .document:
            return "generated-documents"
        }
    }
}

enum GeneratedFileOpenBehavior: Sendable {
    case imagePreview
    case pdfPreview
    case directShare
}

struct GeneratedFileLocalResource: Sendable {
    let localURL: URL
    let filename: String
    let cacheBucket: GeneratedFileCacheBucket
    let openBehavior: GeneratedFileOpenBehavior
}

/// Actor responsible for downloading files from OpenAI (sandbox files from code interpreter output).
actor FileDownloadService {

    static let shared = FileDownloadService()
    static let generatedImageCacheLimitBytes: Int64 = 250 * 1024 * 1024
    static let generatedDocumentCacheLimitBytes: Int64 = 250 * 1024 * 1024

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

    init(
        configurationProvider: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared,
        requestAuthorizer: OpenAIRequestAuthorizer? = nil,
        transport: OpenAIDataTransport? = nil,
        fileManager: FileManager = .default
    ) {
        let authorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(configuration: configurationProvider)
        let resolvedTransport = transport ?? OpenAIURLSessionTransport(
            session: Self.makeDownloadSession()
        )
        self.configurationProvider = configurationProvider
        self.requestAuthorizer = authorizer
        self.transport = resolvedTransport
        self.fileManager = fileManager
        self.cacheStore = GeneratedFileCacheStore(fileManager: fileManager)
    }

    typealias CachedGeneratedFileEntry = GeneratedFileCacheStore.CachedEntry

    private static func makeDownloadSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    /// Download a file by its OpenAI file_id and save to a temp location.
    /// Returns the local file URL.
    /// If a download for the same file reference is already in flight, joins that download.
    func downloadFile(
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

    /// Pre-fetch and persist a generated file so expired sandbox links can still open later.
    func prefetchGeneratedFile(
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

    /// Returns a cached generated file resource if one already exists locally.
    func cachedGeneratedFile(
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

    func generatedImageCacheSize() -> Int64 {
        generatedFileCacheSize(for: .image)
    }

    func clearGeneratedImageCache() {
        clearGeneratedFileCache(for: .image)
    }

    func generatedDocumentCacheSize() -> Int64 {
        generatedFileCacheSize(for: .document)
    }

    func clearGeneratedDocumentCache() {
        clearGeneratedFileCache(for: .document)
    }
}

enum FileDownloadError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case fileNotFound
    case invalidImageData
    case invalidPDFData
    case invalidGeneratedFileData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid file download URL."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let code, let msg): return "File download error (\(code)): \(msg)"
        case .fileNotFound: return "File not found."
        case .invalidImageData: return "The generated image could not be rendered."
        case .invalidPDFData: return "The generated PDF could not be rendered."
        case .invalidGeneratedFileData: return "The generated file could not be downloaded."
        }
    }
}
