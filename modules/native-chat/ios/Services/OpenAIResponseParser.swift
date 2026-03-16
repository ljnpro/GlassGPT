import Foundation

struct OpenAIResponseParser {
    func parseUploadedFileID(responseData: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Upload failed"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }

        let json: [String: Any]
        do {
            json = try JSONCoding.jsonObject(from: responseData)
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to parse upload response")
        }

        guard let fileId = json["id"] as? String else {
            throw OpenAIServiceError.requestFailed("Failed to parse upload response")
        }

        return fileId
    }

    func parseGeneratedTitle(data: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIServiceError.requestFailed("Title generation failed")
        }

        let json: [String: Any]
        do {
            json = try JSONCoding.jsonObject(from: data)
        } catch {
            return "New Chat"
        }

        if let text = OpenAIStreamEventTranslator.extractOutputText(from: json) {
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let words = cleaned.split(separator: " ")
            if words.count > 5 {
                return words.prefix(5).joined(separator: " ")
            }
            return cleaned
        }

        return "New Chat"
    }

    func parseFetchedResponse(data: Data, response: URLResponse) throws -> OpenAIResponseFetchResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Failed to fetch response"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }

        let json: [String: Any]
        do {
            json = try JSONCoding.jsonObject(from: data)
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to parse response")
        }

        let statusString = json["status"] as? String ?? "unknown"
        let status = OpenAIResponseFetchResult.Status(rawValue: statusString) ?? .unknown
        let text = OpenAIStreamEventTranslator.extractOutputText(from: json) ?? ""
        let thinking = OpenAIStreamEventTranslator.extractReasoningText(from: json)
        let annotations = Self.extractCitations(from: json)
        let toolCalls = Self.extractToolCalls(from: json)
        let filePathAnnotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: json)
        let errorMessage = OpenAIStreamEventTranslator.extractErrorMessage(from: json)

        return OpenAIResponseFetchResult(
            status: status,
            text: text,
            thinking: thinking,
            annotations: annotations,
            toolCalls: toolCalls,
            filePathAnnotations: filePathAnnotations,
            errorMessage: errorMessage
        )
    }

    private static func extractCitations(from json: [String: Any]) -> [URLCitation] {
        var annotations: [URLCitation] = []

        guard let output = json["output"] as? [[String: Any]] else {
            return annotations
        }

        for item in output {
            guard let type = item["type"] as? String, type == "message" else { continue }
            guard let content = item["content"] as? [[String: Any]] else { continue }

            for part in content {
                guard let partAnnotations = part["annotations"] as? [[String: Any]] else { continue }

                for ann in partAnnotations {
                    guard
                        let annType = ann["type"] as? String,
                        annType == "url_citation",
                        let url = ann["url"] as? String,
                        let title = ann["title"] as? String
                    else {
                        continue
                    }

                    annotations.append(URLCitation(
                        url: url,
                        title: title,
                        startIndex: ann["start_index"] as? Int ?? 0,
                        endIndex: ann["end_index"] as? Int ?? 0
                    ))
                }
            }
        }

        return annotations
    }

    private static func extractToolCalls(from json: [String: Any]) -> [ToolCallInfo] {
        guard let output = json["output"] as? [[String: Any]] else {
            return []
        }

        var toolCalls: [ToolCallInfo] = []

        for item in output {
            let type = item["type"] as? String ?? ""
            let callId = item["id"] as? String ?? UUID().uuidString

            switch type {
            case "web_search_call":
                var queries: [String]? = nil

                if let action = item["action"] as? [String: Any] {
                    if let query = action["query"] as? String {
                        queries = [query]
                    } else if let queryList = action["queries"] as? [String] {
                        queries = queryList
                    }
                }

                if queries == nil {
                    if let query = item["query"] as? String {
                        queries = [query]
                    } else if let queryList = item["queries"] as? [String] {
                        queries = queryList
                    }
                }

                toolCalls.append(ToolCallInfo(
                    id: callId,
                    type: .webSearch,
                    status: .completed,
                    queries: queries
                ))

            case "code_interpreter_call":
                let code = item["code"] as? String
                let results = extractCodeInterpreterOutputs(from: item)

                toolCalls.append(ToolCallInfo(
                    id: callId,
                    type: .codeInterpreter,
                    status: .completed,
                    code: code,
                    results: results.isEmpty ? nil : results
                ))

            case "file_search_call":
                var queries: [String]? = nil

                if let query = item["query"] as? String {
                    queries = [query]
                } else if let queryList = item["queries"] as? [String] {
                    queries = queryList
                }

                toolCalls.append(ToolCallInfo(
                    id: callId,
                    type: .fileSearch,
                    status: .completed,
                    queries: queries
                ))

            default:
                continue
            }
        }

        return toolCalls
    }

    private static func extractCodeInterpreterOutputs(from item: [String: Any]) -> [String] {
        var outputs: [String] = []

        if let resultArray = item["results"] as? [[String: Any]] {
            outputs.append(contentsOf: resultArray.compactMap { result in
                if let output = result["output"] as? String, !output.isEmpty {
                    return output
                }
                if let text = result["text"] as? String, !text.isEmpty {
                    return text
                }
                if let logs = result["logs"] as? String, !logs.isEmpty {
                    return logs
                }
                return nil
            })
        }

        if let outputArray = item["outputs"] as? [[String: Any]] {
            outputs.append(contentsOf: outputArray.compactMap { output in
                if let text = output["text"] as? String, !text.isEmpty {
                    return text
                }
                if let outputString = output["output"] as? String, !outputString.isEmpty {
                    return outputString
                }
                if let logs = output["logs"] as? String, !logs.isEmpty {
                    return logs
                }
                return nil
            })
        }

        return outputs
    }
}
