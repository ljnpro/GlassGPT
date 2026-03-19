import ChatDomain
import Foundation

public extension OpenAIStreamEventTranslator {
    /// Converts an annotation DTO into a stream event for URL citations or file path annotations.
    /// - Parameter annotation: The annotation DTO to convert.
    /// - Returns: A stream event, or `nil` if the annotation type is not supported.
    static func annotationEvent(from annotation: ResponsesAnnotationDTO) -> StreamEvent? {
        if annotation.type == "url_citation" {
            guard let url = annotation.url, let title = annotation.title else {
                return nil
            }
            return .annotationAdded(
                URLCitation(
                    url: url,
                    title: title,
                    startIndex: annotation.startIndex ?? 0,
                    endIndex: annotation.endIndex ?? 0
                )
            )
        }

        guard isFileCitationAnnotationType(annotation.type),
              let fileId = annotation.fileID,
              !fileId.isEmpty
        else {
            return nil
        }

        return .filePathAnnotationAdded(
            FilePathAnnotation(
                fileId: fileId,
                containerId: annotation.containerID,
                sandboxPath: "",
                filename: annotation.filename,
                startIndex: annotation.startIndex ?? 0,
                endIndex: annotation.endIndex ?? 0
            )
        )
    }

    /// Checks whether the given annotation type represents a file citation.
    /// - Parameter type: The annotation type string.
    /// - Returns: `true` if this is a file path or container file citation annotation.
    static func isFileCitationAnnotationType(_ type: String) -> Bool {
        type == "file_path" || type == "container_file_citation"
    }

    /// Extracts a substring from the given text using character-level indices.
    /// - Parameters:
    ///   - text: The source text.
    ///   - startIndex: The start character index.
    ///   - endIndex: The end character index (exclusive).
    /// - Returns: The extracted substring, or an empty string if indices are out of bounds.
    static func extractAnnotatedSubstring(
        from text: String,
        startIndex: Int,
        endIndex: Int
    ) -> String {
        guard !text.isEmpty, startIndex >= 0, endIndex > startIndex else {
            return ""
        }

        let characters = Array(text)
        guard startIndex < characters.count else {
            return ""
        }

        let safeEndIndex = min(endIndex, characters.count)
        guard safeEndIndex > startIndex else {
            return ""
        }

        return String(characters[startIndex ..< safeEndIndex])
    }
}
