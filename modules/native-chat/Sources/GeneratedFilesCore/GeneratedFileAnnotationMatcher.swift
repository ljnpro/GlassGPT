import ChatDomain
import Foundation

/// Matches sandbox file URLs to their corresponding ``FilePathAnnotation`` entries
/// and extracts filenames for download.
public struct GeneratedFileAnnotationMatcher {
    /// Creates a new matcher.
    public init() {}

    /// Returns the annotation's filename if available, otherwise extracts the filename from the sandbox URL.
    public func requestedFilename(for sandboxURL: String, annotation: FilePathAnnotation?) -> String? {
        annotation?.filename ?? extractFilename(from: sandboxURL)
    }

    /// Returns `true` if the annotation has a container ID or a non-legacy file ID,
    /// meaning it can be downloaded directly from the files API.
    public func annotationCanDownloadDirectly(_ annotation: FilePathAnnotation) -> Bool {
        if let containerId = annotation.containerId, !containerId.isEmpty {
            return true
        }

        return !annotation.fileId.hasPrefix("cfile_")
    }

    /// Finds the best-matching ``FilePathAnnotation`` for a sandbox URL using progressively
    /// looser matching strategies (exact file ID, exact path, suffix, filename, singleton fallback).
    public func findMatchingFilePathAnnotation(
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

        let filename = URL(fileURLWithPath: pathOnly).lastPathComponent
        if !filename.isEmpty,
           let match = annotations.first(where: {
               URL(fileURLWithPath: $0.sandboxPath).lastPathComponent == filename ||
               $0.filename == filename
           }) {
            return match
        }

        if annotations.count == 1 {
            return annotations.first
        }

        return fallback
    }

    private func extractFilename(from sandboxURL: String) -> String? {
        let path: String
        if sandboxURL.hasPrefix("sandbox:") {
            path = String(sandboxURL.dropFirst("sandbox:".count))
        } else {
            path = sandboxURL
        }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return filename.isEmpty ? nil : filename
    }
}
