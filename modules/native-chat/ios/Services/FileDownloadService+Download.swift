import Foundation
import ImageIO
import PDFKit

extension FileDownloadService {
    func performDownload(
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

        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("file_previews", isDirectory: true)

        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let localURL = tempDir.appendingPathComponent(filename)

        removeItemIfExists(at: localURL, logContext: "performDownload.removeStalePreview")
        try data.write(to: localURL)

        return localURL
    }

    func performGeneratedFilePrefetch(
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

    func downloadValidatedGeneratedFile(
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

    func downloadFromAPI(
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

    func downloadKey(fileId: String, containerId: String?) -> String {
        if let containerId, !containerId.isEmpty {
            return "\(containerId):\(fileId)"
        }
        return fileId
    }

    func resolveFilename(
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

    func normalizedFilename(_ candidate: String?, inferredExtension: String?) -> String? {
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

    func inferredFileExtension(from response: URLResponse, data: Data) -> String? {
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

    static func extensionForMimeType(_ mimeType: String) -> String? {
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

    static func extensionForFileSignature(_ data: Data) -> String? {
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
}
