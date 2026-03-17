import Foundation

extension FileDownloadService {
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
}
