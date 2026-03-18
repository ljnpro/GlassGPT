import ChatDomain
import Foundation
import GeneratedFilesCore

public struct GeneratedFileCoordinator {
    private let annotationMatcher = GeneratedFileAnnotationMatcher()
    private let presentationMapper = GeneratedFilePresentationMapper()

    public init() {}

    public func requestedFilename(for sandboxURL: String, annotation: FilePathAnnotation?) -> String? {
        annotationMatcher.requestedFilename(for: sandboxURL, annotation: annotation)
    }

    public func annotationCanDownloadDirectly(_ annotation: FilePathAnnotation) -> Bool {
        annotationMatcher.annotationCanDownloadDirectly(annotation)
    }

    public func findMatchingFilePathAnnotation(
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

    public func presentation(
        for resource: GeneratedFileLocalResource,
        suggestedFilename: String?
    ) -> GeneratedFilePresentation {
        presentationMapper.presentation(for: resource, suggestedFilename: suggestedFilename)
    }

    public func userFacingDownloadError(
        _ error: Error,
        openBehavior: GeneratedFileOpenBehavior
    ) -> String {
        presentationMapper.userFacingDownloadError(error, openBehavior: openBehavior)
    }

    public func generatedOpenBehavior(for annotation: FilePathAnnotation) -> GeneratedFileOpenBehavior {
        presentationMapper.generatedOpenBehavior(for: annotation)
    }
}
