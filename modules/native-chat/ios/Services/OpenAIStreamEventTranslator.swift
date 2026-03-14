import Foundation

enum OpenAIStreamEventTranslator {

    static func extractSequenceNumber(from data: [String: Any]) -> Int? {
        if let value = data["sequence_number"] as? Int {
            return value
        }

        if let value = data["sequence_number"] as? NSNumber {
            return value.intValue
        }

        if let response = data["response"] as? [String: Any],
           let value = response["sequence_number"] as? Int {
            return value
        }

        if let response = data["response"] as? [String: Any],
           let value = response["sequence_number"] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    static func translate(eventType: String, data: [String: Any]) -> StreamEvent? {
        switch eventType {
        case "response.created":
            guard
                let response = data["response"] as? [String: Any],
                let responseId = response["id"] as? String,
                !responseId.isEmpty
            else {
                return nil
            }
            return .responseCreated(responseId)

        case "response.output_text.delta":
            guard let delta = data["delta"] as? String, !delta.isEmpty else { return nil }
            return .textDelta(delta)

        case "response.reasoning_summary_text.delta",
             "response.reasoning_text.delta":
            guard let delta = data["delta"] as? String, !delta.isEmpty else { return nil }
            return .thinkingDelta(delta)

        case "response.reasoning_summary_text.done",
             "response.reasoning_text.done":
            return .thinkingFinished

        case "response.web_search_call.in_progress":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .webSearchStarted(itemId)

        case "response.web_search_call.searching":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .webSearchSearching(itemId)

        case "response.web_search_call.completed":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .webSearchCompleted(itemId)

        case "response.code_interpreter_call.in_progress":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .codeInterpreterStarted(itemId)

        case "response.code_interpreter_call.interpreting":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .codeInterpreterInterpreting(itemId)

        case "response.code_interpreter_call_code.delta":
            guard
                let itemId = data["item_id"] as? String,
                let delta = data["delta"] as? String
            else {
                return nil
            }
            return .codeInterpreterCodeDelta(itemId, delta)

        case "response.code_interpreter_call_code.done":
            guard
                let itemId = data["item_id"] as? String,
                let code = data["code"] as? String
            else {
                return nil
            }
            return .codeInterpreterCodeDone(itemId, code)

        case "response.code_interpreter_call.completed":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .codeInterpreterCompleted(itemId)

        case "response.file_search_call.in_progress":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .fileSearchStarted(itemId)

        case "response.file_search_call.searching":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .fileSearchSearching(itemId)

        case "response.file_search_call.completed":
            guard let itemId = data["item_id"] as? String, !itemId.isEmpty else { return nil }
            return .fileSearchCompleted(itemId)

        case "response.output_text.annotation.added":
            guard
                let annotation = data["annotation"] as? [String: Any],
                let type = annotation["type"] as? String
            else {
                return nil
            }

            if type == "url_citation" {
                guard
                    let url = annotation["url"] as? String,
                    let title = annotation["title"] as? String
                else {
                    return nil
                }

                return .annotationAdded(
                    URLCitation(
                        url: url,
                        title: title,
                        startIndex: annotation["start_index"] as? Int ?? 0,
                        endIndex: annotation["end_index"] as? Int ?? 0
                    )
                )
            }

            if isFileCitationAnnotationType(type) {
                guard
                    let fileId = annotation["file_id"] as? String,
                    !fileId.isEmpty
                else {
                    return nil
                }

                let startIndex = annotation["start_index"] as? Int ?? 0
                let endIndex = annotation["end_index"] as? Int ?? 0

                // The sandbox path isn't directly in the annotation; we'll extract from text context later.
                // For now, store what we have.
                return .filePathAnnotationAdded(
                    FilePathAnnotation(
                        fileId: fileId,
                        sandboxPath: "",
                        filename: annotation["filename"] as? String,
                        startIndex: startIndex,
                        endIndex: endIndex
                    )
                )
            }

            return nil

        case "response.completed":
            let response = data["response"] as? [String: Any] ?? data
            let text = extractOutputText(from: response) ?? ""
            let thinking = extractReasoningText(from: response)
            let filePathAnnotations = extractFilePathAnnotations(from: response)
            return .completed(text, thinking, filePathAnnotations)

        case "response.incomplete":
            let response = data["response"] as? [String: Any] ?? data
            let text = extractOutputText(from: response) ?? ""
            let thinking = extractReasoningText(from: response)
            let filePathAnnotations = extractFilePathAnnotations(from: response)
            let message = extractErrorMessage(from: response)
            return .incomplete(text, thinking, filePathAnnotations, message)

        case "response.failed":
            let response = data["response"] as? [String: Any] ?? data

            if let error = response["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return .error(.requestFailed(message))
            }

            if let message = extractErrorMessage(from: response), !message.isEmpty {
                return .error(.requestFailed(message))
            }

            return .error(.requestFailed("Response generation failed."))

        case "error":
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                return .error(.requestFailed(message))
            }
            return .error(.requestFailed("Unknown streaming error."))

        case "response.queued",
             "response.in_progress",
             "response.output_text.done",
             "response.output_item.added",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.reasoning_summary_part.added",
             "response.reasoning_summary_part.done":
            return nil

        default:
            return nil
        }
    }

    static func extractOutputText(from json: [String: Any]) -> String? {
        if let text = json["output_text"] as? String, !text.isEmpty {
            return text
        }

        guard let output = json["output"] as? [[String: Any]] else {
            return nil
        }

        var texts: [String] = []

        for item in output {
            guard let type = item["type"] as? String, type == "message" else { continue }
            guard let content = item["content"] as? [[String: Any]] else { continue }

            for part in content {
                guard let partType = part["type"] as? String, partType == "output_text" else { continue }
                if let text = part["text"] as? String {
                    texts.append(text)
                }
            }
        }

        let joined = texts.joined()
        return joined.isEmpty ? nil : joined
    }

    static func extractReasoningText(from json: [String: Any]) -> String? {
        var texts: [String] = []

        if let reasoning = json["reasoning"] as? [String: Any] {
            if let text = reasoning["text"] as? String, !text.isEmpty {
                texts.append(text)
            }

            if let summary = reasoning["summary"] as? [[String: Any]] {
                texts.append(contentsOf: summary.compactMap { $0["text"] as? String })
            }
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                guard let type = item["type"] as? String, type == "reasoning" else { continue }

                if let text = item["text"] as? String, !text.isEmpty {
                    texts.append(text)
                }

                if let summary = item["summary"] as? [[String: Any]] {
                    texts.append(contentsOf: summary.compactMap { $0["text"] as? String })
                }

                if let content = item["content"] as? [[String: Any]] {
                    texts.append(contentsOf: content.compactMap { $0["text"] as? String })
                }
            }
        }

        let joined = texts.joined()
        return joined.isEmpty ? nil : joined
    }

    /// Extract file_path annotations from a completed response
    static func extractFilePathAnnotations(from json: [String: Any]) -> [FilePathAnnotation] {
        var annotations: [FilePathAnnotation] = []

        guard let output = json["output"] as? [[String: Any]] else {
            return annotations
        }

        // Also extract the output text to resolve sandbox paths
        var outputText: String = ""

        for item in output {
            guard let type = item["type"] as? String, type == "message" else { continue }
            guard let content = item["content"] as? [[String: Any]] else { continue }

            for part in content {
                guard let partType = part["type"] as? String, partType == "output_text" else { continue }

                if let text = part["text"] as? String {
                    outputText = text
                }

                if let partAnnotations = part["annotations"] as? [[String: Any]] {
                    for ann in partAnnotations {
                        guard
                            let annType = ann["type"] as? String,
                            isFileCitationAnnotationType(annType)
                        else {
                            continue
                        }
                        guard let fileId = ann["file_id"] as? String, !fileId.isEmpty else { continue }

                        let startIndex = ann["start_index"] as? Int ?? 0
                        let endIndex = ann["end_index"] as? Int ?? 0

                        let sandboxPath = extractAnnotatedSubstring(
                            from: outputText,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )

                        annotations.append(FilePathAnnotation(
                            fileId: fileId,
                            sandboxPath: sandboxPath,
                            filename: ann["filename"] as? String,
                            startIndex: startIndex,
                            endIndex: endIndex
                        ))
                    }
                }
            }
        }

        return annotations
    }

    private static func isFileCitationAnnotationType(_ type: String) -> Bool {
        type == "file_path" || type == "container_file_citation"
    }

    private static func extractAnnotatedSubstring(
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

    static func extractErrorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }

        return nil
    }
}
