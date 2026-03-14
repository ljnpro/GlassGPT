import Foundation

/// Actor responsible for downloading files from OpenAI (sandbox files from code interpreter output).
actor FileDownloadService {

    static let shared = FileDownloadService()

    private var inFlightDownloads: [String: Task<URL, Error>] = [:]
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
        let downloadKey = downloadKey(fileId: fileId, containerId: containerId)

        if let existingTask = inFlightDownloads[downloadKey] {
            return try await existingTask.value
        }

        let task = Task<URL, Error> {
            defer { inFlightDownloads[downloadKey] = nil }
            return try await performDownload(
                fileId: fileId,
                containerId: containerId,
                suggestedFilename: suggestedFilename,
                apiKey: apiKey
            )
        }

        inFlightDownloads[downloadKey] = task
        return try await task.value
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

    private func downloadFromAPI(
        fileId: String,
        containerId: String?,
        apiKey: String
    ) async throws -> (Data, URLResponse) {
        let urlString: String

        if let containerId, !containerId.isEmpty {
            urlString = "\(FeatureFlags.openAIBaseURL)/containers/\(containerId)/files/\(fileId)/content"
        } else {
            urlString = "\(FeatureFlags.openAIBaseURL)/files/\(fileId)/content"
        }

        guard let url = URL(string: urlString) else {
            throw FileDownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        FeatureFlags.applyCloudflareAuthorization(to: &request)

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

    private static func extensionForMimeType(_ mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        switch lower {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/svg+xml": return "svg"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        case "text/html": return "html"
        case "application/json": return "json"
        case "application/zip": return "zip"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
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

        if data.count >= 12 {
            let prefix = data.prefix(12)
            if prefix.prefix(4) == Data("RIFF".utf8) && prefix.suffix(4) == Data("WEBP".utf8) {
                return "webp"
            }
        }

        return nil
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

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid file download URL."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let code, let msg): return "File download error (\(code)): \(msg)"
        case .fileNotFound: return "File not found."
        }
    }
}
