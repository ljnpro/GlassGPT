import ChatDomain
import Foundation

enum OpenAIResponseOutputExtractor {
    static func extractOutputText(from response: ResponsesResponseDTO) -> String? {
        let joined = preferredMessageItems(from: response)
            .compactMap(outputText(in:))
            .joined()

        if !joined.isEmpty {
            return joined
        }

        if let text = response.outputText, !text.isEmpty {
            return text
        }

        return nil
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
        let messageItems = preferredMessageItems(from: response)
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
                for annotation in partAnnotations where isFileCitationAnnotationType(annotation.type) {
                    guard let fileId = annotation.fileID, !fileId.isEmpty else { continue }
                    let startIndex = annotation.startIndex ?? 0
                    let endIndex = annotation.endIndex ?? 0

                    annotations.append(
                        FilePathAnnotation(
                            fileId: fileId,
                            containerId: annotation.containerID,
                            sandboxPath: extractAnnotatedSubstring(
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

    static func preferredMessageItems(from response: ResponsesResponseDTO) -> [ResponsesOutputItemDTO] {
        guard let output = response.output else {
            return []
        }

        let messageItems = output.filter { item in
            item.type == "message" && outputText(in: item) != nil
        }

        guard !messageItems.isEmpty else {
            return []
        }

        if let finalAssistant = messageItems.last(where: {
            $0.role == "assistant" && $0.phase == "final_answer"
        }) {
            return [finalAssistant]
        }

        if let completedAssistant = messageItems.last(where: {
            $0.role == "assistant" && $0.status == "completed"
        }) {
            return [completedAssistant]
        }

        if let assistant = messageItems.last(where: { $0.role == "assistant" }) {
            return [assistant]
        }

        if let lastMessage = messageItems.last {
            return [lastMessage]
        }

        return []
    }

    static func outputText(in item: ResponsesOutputItemDTO) -> String? {
        guard let content = item.content else { return nil }
        let text = content
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
        return text.isEmpty ? nil : text
    }
}
