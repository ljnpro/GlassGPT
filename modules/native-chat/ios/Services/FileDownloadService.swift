import Foundation
import ImageIO
import PDFKit

enum GeneratedFileCacheBucket: String, Sendable {
    case image
    case document

    fileprivate var directoryName: String {
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

    private struct GeneratedFilePayload {
        let data: Data
        let filename: String
        let cacheBucket: GeneratedFileCacheBucket
        let openBehavior: GeneratedFileOpenBehavior
    }

    private struct CachedGeneratedFileEntry {
        let directoryURL: URL
        let fileURL: URL
        let size: Int64
        let modifiedAt: Date
    }

    private var inFlightDownloads: [String: Task<URL, Error>] = [:]
    private var inFlightGeneratedFileDownloads: [String: Task<GeneratedFileLocalResource, Error>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
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

    /// Backwards-compatible wrapper for image-only callers.
    func prefetchGeneratedImage(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> URL {
        let resource = try await prefetchGeneratedFile(
            fileId: fileId,
            containerId: containerId,
            suggestedFilename: suggestedFilename,
            apiKey: apiKey
        )

        guard resource.openBehavior == .imagePreview else {
            throw FileDownloadError.invalidImageData
        }

        return resource.localURL
    }

    /// Backwards-compatible wrapper for image-only callers.
    func cachedGeneratedImageURL(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?
    ) -> URL? {
        guard let resource = cachedGeneratedFile(
            fileId: fileId,
            containerId: containerId,
            suggestedFilename: suggestedFilename
        ),
        resource.openBehavior == .imagePreview else {
            return nil
        }

        return resource.localURL
    }

    private func performDownload(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> URL {
        let (data, response) = try await downloadFromAPI(
            fileId: fileId,
            containerId: containerId,
            apiKey: apiKey
        )

        let filename = resolveFilename(
            suggestedFilename: suggestedFilename,
            fileId: fileId,
            response: response,
            data: data
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("file_previews", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let localURL = tempDir.appendingPathComponent(filename)

        try? FileManager.default.removeItem(at: localURL)
        try data.write(to: localURL)

        return localURL
    }

    private func performGeneratedFilePrefetch(
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

        let payload = try await downloadValidatedGeneratedFile(
            fileId: fileId,
            containerId: containerId,
            suggestedFilename: suggestedFilename,
            apiKey: apiKey
        )

        let cacheURL = try storeGeneratedFile(
            data: payload.data,
            filename: payload.filename,
            cacheKey: key,
            bucket: payload.cacheBucket
        )
        trimGeneratedFileCacheIfNeeded(for: payload.cacheBucket)

        return GeneratedFileLocalResource(
            localURL: cacheURL,
            filename: payload.filename,
            cacheBucket: payload.cacheBucket,
            openBehavior: payload.openBehavior
        )
    }

    private func downloadValidatedGeneratedFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> GeneratedFilePayload {
        var lastError: Error = FileDownloadError.invalidGeneratedFileData
        let attemptDirectFlags: [Bool] = FeatureFlags.useCloudflareGateway ? [false, true] : [false]

        for useDirectBaseURL in attemptDirectFlags {
            do {
                let (data, response) = try await downloadFromAPI(
                    fileId: fileId,
                    containerId: containerId,
                    apiKey: apiKey,
                    useDirectBaseURL: useDirectBaseURL
                )

                let filename = resolveFilename(
                    suggestedFilename: suggestedFilename,
                    fileId: fileId,
                    response: response,
                    data: data
                )
                let openBehavior = Self.openBehavior(for: filename)
                let cacheBucket = Self.cacheBucket(for: filename)

                switch openBehavior {
                case .imagePreview:
                    guard Self.isGeneratedImageFilename(filename),
                          Self.isRenderableImageData(data) else {
                        lastError = FileDownloadError.invalidImageData
                        continue
                    }
                case .pdfPreview:
                    guard Self.isGeneratedPDFFilename(filename),
                          Self.isRenderablePDFData(data) else {
                        lastError = FileDownloadError.invalidPDFData
                        continue
                    }
                case .directShare:
                    break
                }

                return GeneratedFilePayload(
                    data: data,
                    filename: filename,
                    cacheBucket: cacheBucket,
                    openBehavior: openBehavior
                )
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func downloadFromAPI(
        fileId: String,
        containerId: String?,
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) async throws -> (Data, URLResponse) {
        let baseURL = useDirectBaseURL ? FeatureFlags.directOpenAIBaseURL : FeatureFlags.openAIBaseURL
        let urlString: String

        if let containerId, !containerId.isEmpty {
            urlString = "\(baseURL)/containers/\(containerId)/files/\(fileId)/content"
        } else {
            urlString = "\(baseURL)/files/\(fileId)/content"
        }

        guard let url = URL(string: urlString) else {
            throw FileDownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        if !useDirectBaseURL {
            FeatureFlags.applyCloudflareAuthorization(to: &request)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FileDownloadError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Download failed"
            throw FileDownloadError.httpError(httpResponse.statusCode, errorMsg)
        }

        return (data, response)
    }

    private func downloadKey(fileId: String, containerId: String?) -> String {
        if let containerId, !containerId.isEmpty {
            return "\(containerId):\(fileId)"
        }
        return fileId
    }

    private func resolveFilename(
        suggestedFilename: String?,
        fileId: String,
        response: URLResponse,
        data: Data
    ) -> String {
        let inferredExtension = inferredFileExtension(from: response, data: data)

        if let suggested = normalizedFilename(suggestedFilename, inferredExtension: inferredExtension) {
            return suggested
        }

        if let httpResponse = response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let filenameRange = disposition.range(of: "filename=\""),
           let endRange = disposition[filenameRange.upperBound...].range(of: "\"") {
            let extracted = String(disposition[filenameRange.upperBound..<endRange.lowerBound])
            if let normalized = normalizedFilename(extracted, inferredExtension: inferredExtension) {
                return normalized
            }
        }

        if let responseSuggested = response.suggestedFilename,
           !responseSuggested.isEmpty,
           responseSuggested != "Unknown",
           let suggested = normalizedFilename(responseSuggested, inferredExtension: inferredExtension) {
            return suggested
        }

        return "\(fileId).\(inferredExtension ?? "bin")"
    }

    private func normalizedFilename(_ candidate: String?, inferredExtension: String?) -> String? {
        guard let candidate else { return nil }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !sanitized.isEmpty else { return nil }

        if !URL(fileURLWithPath: sanitized).pathExtension.isEmpty {
            return sanitized
        }

        if let inferredExtension, !inferredExtension.isEmpty {
            return "\(sanitized).\(inferredExtension)"
        }

        return sanitized
    }

    private func inferredFileExtension(from response: URLResponse, data: Data) -> String? {
        if let mimeType = response.mimeType,
           let ext = Self.extensionForMimeType(mimeType) {
            return ext
        }

        return Self.extensionForFileSignature(data)
    }

    nonisolated static func openBehavior(for filename: String?) -> GeneratedFileOpenBehavior {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return .imagePreview
        case "pdf":
            return .pdfPreview
        default:
            return .directShare
        }
    }

    nonisolated static func cacheBucket(for filename: String?) -> GeneratedFileCacheBucket {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return .image
        default:
            return .document
        }
    }

    nonisolated static func isGeneratedImageFilename(_ filename: String?) -> Bool {
        guard let filename else { return false }

        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return true
        default:
            return false
        }
    }

    nonisolated static func isGeneratedPDFFilename(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf"
    }

    private nonisolated static func isRenderableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil
    }

    private nonisolated static func isRenderablePDFData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return PDFDocument(data: data) != nil
    }

    private static func extensionForMimeType(_ mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        switch lower {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/svg+xml": return "svg"
        case "image/webp": return "webp"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        case "image/x-icon": return "ico"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        case "text/tab-separated-values": return "tsv"
        case "text/html": return "html"
        case "text/markdown": return "md"
        case "application/json": return "json"
        case "application/geo+json": return "geojson"
        case "application/xml", "text/xml": return "xml"
        case "application/yaml", "text/yaml": return "yaml"
        case "application/x-yaml": return "yml"
        case "application/toml": return "toml"
        case "application/zip": return "zip"
        case "application/gzip": return "gz"
        case "application/x-bzip2": return "bz2"
        case "application/x-xz": return "xz"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
        case "application/vnd.oasis.opendocument.spreadsheet": return "ods"
        case "application/vnd.oasis.opendocument.text": return "odt"
        case "application/vnd.oasis.opendocument.presentation": return "odp"
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/mpeg": return "mp3"
        case "audio/ogg": return "ogg"
        case "audio/flac": return "flac"
        default:
            if lower.hasPrefix("text/") { return "txt" }
            if lower.hasPrefix("image/") { return lower.replacingOccurrences(of: "image/", with: "") }
            return nil
        }
    }

    private static func extensionForFileSignature(_ data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }

        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }

        if data.starts(with: Array("GIF8".utf8)) {
            return "gif"
        }

        if data.starts(with: Array("%PDF".utf8)) {
            return "pdf"
        }

        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return "zip"
        }

        if data.starts(with: [0x1F, 0x8B]) {
            return "gz"
        }

        if data.starts(with: Array("BZh".utf8)) {
            return "bz2"
        }

        if data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
            return "xz"
        }

        if data.starts(with: Array("SQLite format 3\u{0}".utf8)) {
            return "sqlite"
        }

        if data.count >= 12 {
            let prefix = data.prefix(12)
            if prefix.prefix(4) == Data("RIFF".utf8) && prefix.suffix(4) == Data("WEBP".utf8) {
                return "webp"
            }
            if prefix.prefix(4) == Data("RIFF".utf8) && prefix.suffix(4) == Data("WAVE".utf8) {
                return "wav"
            }
        }

        if data.starts(with: Array("OggS".utf8)) {
            return "ogg"
        }

        if data.starts(with: Array("fLaC".utf8)) {
            return "flac"
        }

        return nil
    }

    private func generatedCacheRootURL(
        for bucket: GeneratedFileCacheBucket,
        createIfNeeded: Bool
    ) -> URL? {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let rootURL = cachesURL.appendingPathComponent(bucket.directoryName, isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL
    }

    private func generatedCacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        guard let rootURL = generatedCacheRootURL(for: bucket, createIfNeeded: true) else {
            throw FileDownloadError.invalidURL
        }

        return rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
    }

    private func storeGeneratedFile(
        data: Data,
        filename: String,
        cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws -> URL {
        let directoryURL = try generatedCacheDirectoryURL(for: cacheKey, bucket: bucket)
        try? FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        touchGeneratedFile(at: fileURL)
        return fileURL
    }

    private func existingGeneratedFileCacheEntry(
        cacheKey: String,
        suggestedFilename: String?,
        bucket: GeneratedFileCacheBucket
    ) -> CachedGeneratedFileEntry? {
        guard let rootURL = generatedCacheRootURL(for: bucket, createIfNeeded: false) else {
            return nil
        }

        let directoryURL = rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        if let normalized = normalizedFilename(suggestedFilename, inferredExtension: nil) {
            let preferredURL = directoryURL.appendingPathComponent(normalized)
            if let entry = cachedGeneratedFileEntry(fileURL: preferredURL, directoryURL: directoryURL) {
                return entry
            }
        }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        for fileURL in urls where !isDirectoryURL(fileURL) {
            if let entry = cachedGeneratedFileEntry(fileURL: fileURL, directoryURL: directoryURL) {
                return entry
            }
        }

        return nil
    }

    private func cachedGeneratedFileEntry(
        fileURL: URL,
        directoryURL: URL
    ) -> CachedGeneratedFileEntry? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
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

    private func generatedFileCacheEntries(for bucket: GeneratedFileCacheBucket) -> [CachedGeneratedFileEntry] {
        guard let rootURL = generatedCacheRootURL(for: bucket, createIfNeeded: false),
              let directoryURLs = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }

        return directoryURLs.compactMap { directoryURL in
            guard isDirectoryURL(directoryURL),
                  let fileURLs = try? FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil
                  ) else {
                return nil
            }

            for fileURL in fileURLs where !isDirectoryURL(fileURL) {
                if let entry = cachedGeneratedFileEntry(fileURL: fileURL, directoryURL: directoryURL) {
                    return entry
                }
            }

            return nil
        }
    }

    private func generatedFileCacheSize(for bucket: GeneratedFileCacheBucket) -> Int64 {
        generatedFileCacheEntries(for: bucket).reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.size
        }
    }

    private func trimGeneratedFileCacheIfNeeded(for bucket: GeneratedFileCacheBucket) {
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
            try? FileManager.default.removeItem(at: entry.directoryURL)
        }
    }

    private func touchGeneratedFileCacheEntry(_ entry: CachedGeneratedFileEntry) {
        touchGeneratedFile(at: entry.fileURL)
    }

    private func touchGeneratedFile(at fileURL: URL) {
        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fileURL.path)
        try? FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )
    }

    private func clearGeneratedFileCache(for bucket: GeneratedFileCacheBucket) {
        guard let cacheRoot = generatedCacheRootURL(for: bucket, createIfNeeded: false) else {
            return
        }

        try? FileManager.default.removeItem(at: cacheRoot)
    }

    private func sanitizedCacheKey(_ cacheKey: String) -> String {
        cacheKey.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    func cleanupCache() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("file_previews", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
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
