import Foundation

extension FileDownloadService {
    /// Prefetches a generated image and validates it can be rendered, returning its local URL.
    /// - Throws: ``FileDownloadError/invalidImageData`` if the downloaded file is not a valid image.
    public func prefetchGeneratedImage(
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

    /// Returns the local URL of a cached generated image, or `nil` if not cached or not an image.
    public func cachedGeneratedImageURL(
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
}
