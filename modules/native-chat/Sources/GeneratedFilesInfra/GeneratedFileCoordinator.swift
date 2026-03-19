import ChatDomain
import Foundation
import GeneratedFilesCore

/// High-level coordinator that combines annotation matching and presentation mapping
/// for generated file operations.
public struct GeneratedFileCoordinator {
    private let annotationMatcher = GeneratedFileAnnotationMatcher()
    private let presentationMapper = GeneratedFilePresentationMapper()

    /// Creates a new coordinator.
    public init() {}

    /// Returns the best filename for a sandbox URL, using the annotation's filename if available.
    public func requestedFilename(for sandboxURL: String, annotation: FilePathAnnotation?) -> String? {
        annotationMatcher.requestedFilename(for: sandboxURL, annotation: annotation)
    }

    /// Returns `true` if the annotation supports direct download from the files API.
    public func annotationCanDownloadDirectly(_ annotation: FilePathAnnotation) -> Bool {
        annotationMatcher.annotationCanDownloadDirectly(annotation)
    }

    /// Finds the best-matching file-path annotation for a given sandbox URL.
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

    /// Maps a local resource to its presentation (preview or share).
    public func presentation(
        for resource: GeneratedFileLocalResource,
        suggestedFilename: String?
    ) -> GeneratedFilePresentation {
        presentationMapper.presentation(for: resource, suggestedFilename: suggestedFilename)
    }

    /// Converts a download error into a user-facing message appropriate for the file's open behavior.
    public func userFacingDownloadError(
        _ error: Error,
        openBehavior: GeneratedFileOpenBehavior
    ) -> String {
        presentationMapper.userFacingDownloadError(error, openBehavior: openBehavior)
    }

    /// Determines the open behavior for a file based on its annotation metadata.
    public func generatedOpenBehavior(for annotation: FilePathAnnotation) -> GeneratedFileOpenBehavior {
        presentationMapper.generatedOpenBehavior(for: annotation)
    }
}
