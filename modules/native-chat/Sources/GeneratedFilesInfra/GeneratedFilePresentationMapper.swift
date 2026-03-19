import ChatDomain
import Foundation
import GeneratedFilesCore

/// The resolved presentation mode for a generated file.
public enum GeneratedFilePresentation {
    /// Show the file in the in-app preview viewer.
    case preview(FilePreviewItem)
    /// Present the file via the system share sheet.
    case share(SharedGeneratedFileItem)
}

/// Maps a ``GeneratedFileLocalResource`` to its user-facing presentation and builds
/// error messages for failed downloads.
public struct GeneratedFilePresentationMapper {
    /// Creates a new presentation mapper.
    public init() {}

    /// Builds the appropriate ``GeneratedFilePresentation`` for a local resource.
    public func presentation(
        for resource: GeneratedFileLocalResource,
        suggestedFilename: String?
    ) -> GeneratedFilePresentation {
        switch resource.openBehavior {
        case .imagePreview:
            .preview(
                makePreviewItem(
                    url: resource.localURL,
                    kind: .generatedImage,
                    suggestedFilename: resource.filename.isEmpty ? suggestedFilename : resource.filename
                )
            )
        case .pdfPreview:
            .preview(
                makePreviewItem(
                    url: resource.localURL,
                    kind: .generatedPDF,
                    suggestedFilename: resource.filename.isEmpty ? suggestedFilename : resource.filename
                )
            )
        case .directShare:
            .share(
                SharedGeneratedFileItem(
                    url: resource.localURL,
                    filename: resource.filename
                )
            )
        }
    }

    /// Returns a user-facing error message for a failed file download, customized by open behavior.
    public func userFacingDownloadError(
        _ error: Error,
        openBehavior: GeneratedFileOpenBehavior
    ) -> String {
        if let fileError = error as? FileDownloadError {
            switch (openBehavior, fileError) {
            case (.imagePreview, .fileNotFound):
                return "This generated image is no longer available. Please regenerate it."
            case let (.imagePreview, .httpError(statusCode, _)) where statusCode == 404 || statusCode == 410:
                return "This generated image has expired and can no longer be downloaded. Please regenerate it."
            case (.imagePreview, .invalidImageData):
                return "This generated image could not be rendered."
            case (.pdfPreview, .fileNotFound):
                return "This generated file is no longer available. Please regenerate it."
            case let (.pdfPreview, .httpError(statusCode, _)) where statusCode == 404 || statusCode == 410:
                return "This generated file has expired and can no longer be downloaded. Please regenerate it."
            case (.pdfPreview, .invalidPDFData):
                return "This generated PDF could not be rendered."
            case (.directShare, .fileNotFound):
                return "This generated file is no longer available. Please regenerate it."
            case let (.directShare, .httpError(statusCode, _)) where statusCode == 404 || statusCode == 410:
                return "This generated file has expired and can no longer be downloaded. Please regenerate it."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    /// Determines the open behavior for a file based on its annotation's filename or sandbox path extension.
    public func generatedOpenBehavior(for annotation: FilePathAnnotation) -> GeneratedFileOpenBehavior {
        if let filename = annotation.filename {
            return openBehavior(for: filename)
        }

        let sandboxPath = annotation.sandboxPath
        guard !sandboxPath.isEmpty else { return .directShare }
        let filename = URL(fileURLWithPath: sandboxPath).lastPathComponent
        return openBehavior(for: filename)
    }

    private func openBehavior(for filename: String?) -> GeneratedFileOpenBehavior {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            .imagePreview
        case "pdf":
            .pdfPreview
        default:
            .directShare
        }
    }

    private func makePreviewItem(
        url: URL,
        kind: FilePreviewKind,
        suggestedFilename: String?
    ) -> FilePreviewItem {
        let viewerFilename = previewViewerFilename(for: suggestedFilename) ?? url.lastPathComponent
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let displayName = previewDisplayName(for: viewerFilename) ?? (fallbackName.isEmpty ? viewerFilename : fallbackName)
        return FilePreviewItem(
            url: url,
            kind: kind,
            displayName: displayName,
            viewerFilename: viewerFilename
        )
    }

    private func previewViewerFilename(for filename: String?) -> String? {
        guard let filename else { return nil }
        let sanitizedFilename = URL(fileURLWithPath: filename).lastPathComponent
        return sanitizedFilename.isEmpty ? nil : sanitizedFilename
    }

    private func previewDisplayName(for filename: String?) -> String? {
        guard let filename else { return nil }
        let trimmed = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return trimmed.isEmpty ? nil : trimmed
    }
}
