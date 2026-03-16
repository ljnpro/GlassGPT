import Foundation

enum GeneratedFilePresentation {
    case preview(FilePreviewItem)
    case share(SharedGeneratedFileItem)
}

struct GeneratedFileCoordinator {
    func requestedFilename(for sandboxURL: String, annotation: FilePathAnnotation?) -> String? {
        annotation?.filename ?? extractFilename(from: sandboxURL)
    }

    func annotationCanDownloadDirectly(_ annotation: FilePathAnnotation) -> Bool {
        if let containerId = annotation.containerId, !containerId.isEmpty {
            return true
        }

        return !annotation.fileId.hasPrefix("cfile_")
    }

    func findMatchingFilePathAnnotation(
        in annotations: [FilePathAnnotation],
        sandboxURL: String,
        fallback: FilePathAnnotation?
    ) -> FilePathAnnotation? {
        if let fallback,
           let exactFileIdMatch = annotations.first(where: { $0.fileId == fallback.fileId }) {
            return exactFileIdMatch
        }

        if let exact = annotations.first(where: { $0.sandboxPath == sandboxURL }) {
            return exact
        }

        let pathOnly: String
        if sandboxURL.hasPrefix("sandbox:") {
            pathOnly = String(sandboxURL.dropFirst("sandbox:".count))
        } else {
            pathOnly = sandboxURL
        }

        if let match = annotations.first(where: {
            $0.sandboxPath == pathOnly ||
            $0.sandboxPath.hasSuffix(pathOnly) ||
            pathOnly.hasSuffix($0.sandboxPath)
        }) {
            return match
        }

        let filename = (pathOnly as NSString).lastPathComponent
        if !filename.isEmpty,
           let match = annotations.first(where: {
               ($0.sandboxPath as NSString).lastPathComponent == filename ||
               $0.filename == filename
           }) {
            return match
        }

        if annotations.count == 1 {
            return annotations.first
        }

        return fallback
    }

    func presentation(
        for resource: GeneratedFileLocalResource,
        suggestedFilename: String?
    ) -> GeneratedFilePresentation {
        switch resource.openBehavior {
        case .imagePreview:
            return .preview(
                makePreviewItem(
                    url: resource.localURL,
                    kind: .generatedImage,
                    suggestedFilename: resource.filename.isEmpty ? suggestedFilename : resource.filename
                )
            )
        case .pdfPreview:
            return .preview(
                makePreviewItem(
                    url: resource.localURL,
                    kind: .generatedPDF,
                    suggestedFilename: resource.filename.isEmpty ? suggestedFilename : resource.filename
                )
            )
        case .directShare:
            return .share(
                SharedGeneratedFileItem(
                    url: resource.localURL,
                    filename: resource.filename
                )
            )
        }
    }

    func userFacingDownloadError(
        _ error: Error,
        openBehavior: GeneratedFileOpenBehavior
    ) -> String {
        if let fileError = error as? FileDownloadError {
            switch (openBehavior, fileError) {
            case (.imagePreview, .fileNotFound):
                return "This generated image is no longer available. Please regenerate it."
            case (.imagePreview, .httpError(let statusCode, _)) where statusCode == 404 || statusCode == 410:
                return "This generated image has expired and can no longer be downloaded. Please regenerate it."
            case (.imagePreview, .invalidImageData):
                return "This generated image could not be rendered."
            case (.pdfPreview, .fileNotFound):
                return "This generated file is no longer available. Please regenerate it."
            case (.pdfPreview, .httpError(let statusCode, _)) where statusCode == 404 || statusCode == 410:
                return "This generated file has expired and can no longer be downloaded. Please regenerate it."
            case (.pdfPreview, .invalidPDFData):
                return "This generated PDF could not be rendered."
            case (.directShare, .fileNotFound):
                return "This generated file is no longer available. Please regenerate it."
            case (.directShare, .httpError(let statusCode, _)) where statusCode == 404 || statusCode == 410:
                return "This generated file has expired and can no longer be downloaded. Please regenerate it."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    func generatedOpenBehavior(for annotation: FilePathAnnotation) -> GeneratedFileOpenBehavior {
        if let filename = annotation.filename {
            return FileDownloadService.openBehavior(for: filename)
        }

        let sandboxPath = annotation.sandboxPath
        guard !sandboxPath.isEmpty else { return .directShare }
        let filename = (sandboxPath as NSString).lastPathComponent
        return FileDownloadService.openBehavior(for: filename)
    }

    private func extractFilename(from sandboxURL: String) -> String? {
        let path: String
        if sandboxURL.hasPrefix("sandbox:") {
            path = String(sandboxURL.dropFirst("sandbox:".count))
        } else {
            path = sandboxURL
        }
        let filename = (path as NSString).lastPathComponent
        return filename.isEmpty ? nil : filename
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
