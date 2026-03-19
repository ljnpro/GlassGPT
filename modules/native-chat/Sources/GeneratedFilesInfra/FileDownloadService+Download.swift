import Foundation
import GeneratedFilesCore
import os

private let fileDownloadSignposter = OSSignposter(subsystem: "GlassGPT", category: "files")

extension FileDownloadService {
    func performDownload(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> URL {
        let signpostID = fileDownloadSignposter.makeSignpostID()
        let signpostState = fileDownloadSignposter.beginInterval("PerformDownload", id: signpostID)
        defer { fileDownloadSignposter.endInterval("PerformDownload", signpostState) }

        let (data, response) = try await downloadClient.downloadFromAPI(
            fileId: fileId,
            containerId: containerId,
            apiKey: apiKey
        )

        let filename = namingResolver.resolveFilename(
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
        let key = namingResolver.downloadKey(fileId: fileId, containerId: containerId)

        if let cached = cachedGeneratedFile(
            fileId: fileId,
            containerId: containerId,
            suggestedFilename: suggestedFilename
        ) {
            return cached
        }

        let payload = try await downloadClient.downloadValidatedGeneratedFile(
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
}
