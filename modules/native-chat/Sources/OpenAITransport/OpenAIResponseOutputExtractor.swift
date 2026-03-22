import ChatDomain
import Foundation

enum OpenAIResponseOutputExtractor {
    static func extractOutputText(from response: ResponsesResponseDTO) -> String? {
        if let text = response.outputText, !text.isEmpty {
            return text
        }

        let joined = OpenAIResponseOutputSelection.preferredMessageItems(from: response)
            .compactMap(OpenAIResponseOutputSelection.outputText(in:))
            .joined()

        return joined.isEmpty ? nil : joined
    }

    static func extractReasoningText(from response: ResponsesResponseDTO) -> String? {
        var texts: [String] = []

        if let reasoning = response.reasoning {
            if let text = reasoning.text, !text.isEmpty {
                texts.append(text)
            }
            if let summary = reasoning.summary {
                texts.append(contentsOf: summary.compactMap(\.text))
            }
        }

        if let output = response.output {
            for item in output where item.type == "reasoning" {
                if let text = item.text, !text.isEmpty {
                    texts.append(text)
                }
                if let summary = item.summary {
                    texts.append(contentsOf: summary.compactMap(\.text))
                }
                if let content = item.content {
                    texts.append(contentsOf: content.compactMap(\.text))
                }
            }
        }

        let joined = texts.joined()
        return joined.isEmpty ? nil : joined
    }

    static func extractFilePathAnnotations(from response: ResponsesResponseDTO) -> [FilePathAnnotation] {
        let messageItems = OpenAIResponseOutputSelection.preferredMessageItems(from: response)
        guard !messageItems.isEmpty else {
            return []
        }

        var annotations: [FilePathAnnotation] = []
        var outputText = ""

        for item in messageItems {
            guard let content = item.content else { continue }

            for part in content where part.type == "output_text" {
                if let text = part.text {
                    outputText = text
                }

                guard let partAnnotations = part.annotations else { continue }
                for annotation in partAnnotations where OpenAIStreamEventTranslator.isFileCitationAnnotationType(annotation.type) {
                    guard let fileId = annotation.fileID, !fileId.isEmpty else { continue }
                    let startIndex = annotation.startIndex ?? 0
                    let endIndex = annotation.endIndex ?? 0

                    annotations.append(
                        FilePathAnnotation(
                            fileId: fileId,
                            containerId: annotation.containerID,
                            sandboxPath: OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                                from: outputText,
                                startIndex: startIndex,
                                endIndex: endIndex
                            ),
                            filename: annotation.filename,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    )
                }
            }
        }

        return annotations
    }

    static func extractErrorMessage(from response: ResponsesResponseDTO) -> String? {
        if let message = response.error?.message, !message.isEmpty {
            return message
        }
        if let message = response.message, !message.isEmpty {
            return message
        }
        return nil
    }
}
