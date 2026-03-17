import Foundation

enum GeneratedFilePresentation {
    case preview(FilePreviewItem)
    case share(SharedGeneratedFileItem)
}

struct GeneratedFileCoordinator {
    private let annotationMatcher = GeneratedFileAnnotationMatcher()
    private let presentationMapper = GeneratedFilePresentationMapper()

    func requestedFilename(for sandboxURL: String, annotation: FilePathAnnotation?) -> String? {
        annotationMatcher.requestedFilename(for: sandboxURL, annotation: annotation)
    }

    func annotationCanDownloadDirectly(_ annotation: FilePathAnnotation) -> Bool {
        annotationMatcher.annotationCanDownloadDirectly(annotation)
    }

    func findMatchingFilePathAnnotation(
        in annotations: [FilePathAnnotation],
        sandboxURL: String,
        fallback: FilePathAnnotation?
    ) -> FilePathAnnotation? {
        annotationMatcher.findMatchingFilePathAnnotation(
            in: annotations,
            sandboxURL: sandboxURL,
            fallback: fallback
        )
    }

    func presentation(
        for resource: GeneratedFileLocalResource,
        suggestedFilename: String?
    ) -> GeneratedFilePresentation {
        presentationMapper.presentation(for: resource, suggestedFilename: suggestedFilename)
    }

    func userFacingDownloadError(
        _ error: Error,
        openBehavior: GeneratedFileOpenBehavior
    ) -> String {
        presentationMapper.userFacingDownloadError(error, openBehavior: openBehavior)
    }

    func generatedOpenBehavior(for annotation: FilePathAnnotation) -> GeneratedFileOpenBehavior {
        presentationMapper.generatedOpenBehavior(for: annotation)
    }
}
