import Foundation

struct GeneratedFileAnnotationMatcher {
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

    // MARK: - Private

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
}
