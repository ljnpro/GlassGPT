import BackendClient
import ChatDomain
import ChatPresentation
import Foundation
import GeneratedFilesCache
import GeneratedFilesCore

@MainActor
package final class GeneratedFileInteractionCoordinator {
    private let client: any BackendRequesting
    private let cacheManager: GeneratedFileCacheManager
    private let filePreviewStore: FilePreviewStore
    private let annotationMatcher = GeneratedFileAnnotationMatcher()

    package init(
        client: any BackendRequesting,
        cacheManager: GeneratedFileCacheManager,
        filePreviewStore: FilePreviewStore
    ) {
        self.client = client
        self.cacheManager = cacheManager
        self.filePreviewStore = filePreviewStore
    }

    package func handleSandboxLinkTap(_ sandboxURL: String, annotation: FilePathAnnotation?) async {
        filePreviewStore.fileDownloadError = nil

        guard let annotation else {
            filePreviewStore.fileDownloadError = "This generated file is no longer available."
            return
        }
        guard annotationMatcher.annotationCanDownloadDirectly(annotation) else {
            filePreviewStore.fileDownloadError = "This generated file cannot be downloaded yet."
            return
        }

        let requestedFilename = annotationMatcher.requestedFilename(
            for: sandboxURL,
            annotation: annotation
        )
        var descriptor = GeneratedFileDescriptor(
            fileID: annotation.fileId,
            containerID: annotation.containerId,
            filename: requestedFilename
        )

        filePreviewStore.isDownloadingFile = true
        defer { filePreviewStore.isDownloadingFile = false }

        do {
            if let cached = await cacheManager.cachedGeneratedFile(for: descriptor) {
                present(cached)
                return
            }

            let download = try await client.downloadGeneratedFile(
                fileId: descriptor.fileID,
                containerId: descriptor.containerID
            )
            guard !download.data.isEmpty else {
                throw BackendAPIError.invalidResponse
            }

            descriptor = GeneratedFileDescriptor(
                fileID: descriptor.fileID,
                containerID: descriptor.containerID,
                filename: descriptor.filename,
                mediaType: download.contentType
            )
            let localResource = try await cacheManager.storeGeneratedFile(
                data: download.data,
                descriptor: descriptor
            )
            present(localResource)
        } catch {
            filePreviewStore.fileDownloadError = error.localizedDescription
        }
    }

    private func present(_ localResource: GeneratedFileLocalResource) {
        filePreviewStore.sharedGeneratedFileItem = nil
        filePreviewStore.filePreviewItem = nil

        switch localResource.openBehavior {
        case .imagePreview:
            filePreviewStore.filePreviewItem = FilePreviewItem(
                url: localResource.localURL,
                kind: .generatedImage,
                displayName: localResource.filename,
                viewerFilename: localResource.filename
            )
        case .pdfPreview:
            filePreviewStore.filePreviewItem = FilePreviewItem(
                url: localResource.localURL,
                kind: .generatedPDF,
                displayName: localResource.filename,
                viewerFilename: localResource.filename
            )
        case .directShare:
            filePreviewStore.sharedGeneratedFileItem = SharedGeneratedFileItem(
                url: localResource.localURL,
                filename: localResource.filename
            )
        }
    }
}
