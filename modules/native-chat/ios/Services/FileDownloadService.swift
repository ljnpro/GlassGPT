import Foundation

/// Actor responsible for downloading files from OpenAI (sandbox files from code interpreter output).
/// Handles both direct API access and relay-proxied downloads.
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
    /// If a download for the same fileId is already in flight, joins that download.
    func downloadFile(fileId: String, suggestedFilename: String?, apiKey: String) async throws -> URL {
        // Deduplicate in-flight downloads
        if let existingTask = inFlightDownloads[fileId] {
            return try await existingTask.value
        }

        let task = Task<URL, Error> {
            defer { inFlightDownloads[fileId] = nil }
            return try await performDownload(fileId: fileId, suggestedFilename: suggestedFilename, apiKey: apiKey)
        }

        inFlightDownloads[fileId] = task
        return try await task.value
    }

    private func performDownload(fileId: String, suggestedFilename: String?, apiKey: String) async throws -> URL {
        let isRelayConfigured = FeatureFlags.isRelayConfigured

        let data: Data
        let response: URLResponse

        if isRelayConfigured {
            (data, response) = try await downloadViaRelay(fileId: fileId, apiKey: apiKey)
        } else {
            (data, response) = try await downloadDirect(fileId: fileId, apiKey: apiKey)
        }

        // Determine filename
        let filename = resolveFilename(
            suggestedFilename: suggestedFilename,
            fileId: fileId,
            response: response
        )

        // Save to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("file_previews", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let localURL = tempDir.appendingPathComponent(filename)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: localURL)
        try data.write(to: localURL)

        return localURL
    }

    private func downloadDirect(fileId: String, apiKey: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "https://api.openai.com/v1/files/\(fileId)/content") else {
            throw FileDownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

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

    private func downloadViaRelay(fileId: String, apiKey: String) async throws -> (Data, URLResponse) {
        let baseURL = try RelayAPIService.configuredBaseURL()
        let basePath = RELAY_HTTP_BASE_PATH.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL
            .appendingPathComponent(basePath)
            .appendingPathComponent("files")
            .appendingPathComponent(fileId)
            .appendingPathComponent("content")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

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

    private func resolveFilename(suggestedFilename: String?, fileId: String, response: URLResponse) -> String {
        // Try suggested filename first
        if let suggested = suggestedFilename, !suggested.isEmpty {
            return suggested
        }

        // Try Content-Disposition header
        if let httpResponse = response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let filenameRange = disposition.range(of: "filename=\""),
           let endRange = disposition[filenameRange.upperBound...].range(of: "\"") {
            let extracted = String(disposition[filenameRange.upperBound..<endRange.lowerBound])
            if !extracted.isEmpty {
                return extracted
            }
        }

        // Try suggested filename from URLResponse
        if let suggested = response.suggestedFilename, !suggested.isEmpty, suggested != "Unknown" {
            return suggested
        }

        // Determine extension from MIME type
        let ext: String
        if let mimeType = response.mimeType {
            ext = Self.extensionForMimeType(mimeType)
        } else {
            ext = "bin"
        }

        return "\(fileId).\(ext)"
    }

    private static func extensionForMimeType(_ mimeType: String) -> String {
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
            return "bin"
        }
    }

    /// Clean up all cached preview files
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
