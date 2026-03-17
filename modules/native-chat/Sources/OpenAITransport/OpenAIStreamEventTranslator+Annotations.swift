import ChatDomain
import Foundation

extension OpenAIStreamEventTranslator {
    public static func annotationEvent(from annotation: ResponsesAnnotationDTO) -> StreamEvent? {
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
              !fileId.isEmpty else {
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

    public static func isFileCitationAnnotationType(_ type: String) -> Bool {
        type == "file_path" || type == "container_file_citation"
    }

    public static func extractAnnotatedSubstring(
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

        return String(characters[startIndex..<safeEndIndex])
    }
}
