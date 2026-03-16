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
}
