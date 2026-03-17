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

        do {
            return try JSONCoding.decode(UploadedFileResponseDTO.self, from: responseData).id
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to parse upload response")
        }
    }

    func parseGeneratedTitle(data: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIServiceError.requestFailed("Title generation failed")
        }

        let responseDTO: ResponsesResponseDTO
        do {
            responseDTO = try JSONCoding.decode(ResponsesResponseDTO.self, from: data)
        } catch {
            return "New Chat"
        }

        if let text = OpenAIStreamEventTranslator.extractOutputText(from: responseDTO) {
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

        let responseDTO: ResponsesResponseDTO
        do {
            responseDTO = try JSONCoding.decode(ResponsesResponseDTO.self, from: data)
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to parse response")
        }

        let statusString = responseDTO.status ?? "unknown"
        let status = OpenAIResponseFetchResult.Status(rawValue: statusString) ?? .unknown
        let text = OpenAIStreamEventTranslator.extractOutputText(from: responseDTO) ?? ""
        let thinking = OpenAIStreamEventTranslator.extractReasoningText(from: responseDTO)
        let annotations = Self.extractCitations(from: responseDTO)
        let toolCalls = Self.extractToolCalls(from: responseDTO)
        let filePathAnnotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: responseDTO)
        let errorMessage = OpenAIStreamEventTranslator.extractErrorMessage(from: responseDTO)

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

    private static func extractCitations(from response: ResponsesResponseDTO) -> [URLCitation] {
        var annotations: [URLCitation] = []

        guard let output = response.output else {
            return annotations
        }

        for item in output {
            guard item.type == "message", let content = item.content else { continue }

            for part in content {
                guard let partAnnotations = part.annotations else { continue }

                for ann in partAnnotations {
                    guard
                        ann.type == "url_citation",
                        let url = ann.url,
                        let title = ann.title
                    else {
                        continue
                    }

                    annotations.append(URLCitation(
                        url: url,
                        title: title,
                        startIndex: ann.startIndex ?? 0,
                        endIndex: ann.endIndex ?? 0
                    ))
                }
            }
        }

        return annotations
    }

    private static func extractToolCalls(from response: ResponsesResponseDTO) -> [ToolCallInfo] {
        guard let output = response.output else {
            return []
        }

        var toolCalls: [ToolCallInfo] = []

        for item in output {
            let type = item.type
            let callId = item.id ?? UUID().uuidString

            switch type {
            case "web_search_call":
                var queries: [String]? = nil

                if let action = item.action {
                    if let query = action.query {
                        queries = [query]
                    } else if let queryList = action.queries {
                        queries = queryList
                    }
                }

                if queries == nil {
                    if let query = item.query {
                        queries = [query]
                    } else if let queryList = item.queries {
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
                let code = item.code
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

                if let query = item.query {
                    queries = [query]
                } else if let queryList = item.queries {
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

    private static func extractCodeInterpreterOutputs(from item: ResponsesOutputItemDTO) -> [String] {
        var outputs: [String] = []

        if let resultArray = item.results {
            outputs.append(contentsOf: resultArray.compactMap { result in
                if let output = result.output, !output.isEmpty {
                    return output
                }
                if let text = result.text, !text.isEmpty {
                    return text
                }
                if let logs = result.logs, !logs.isEmpty {
                    return logs
                }
                return nil
            })
        }

        if let outputArray = item.outputs {
            outputs.append(contentsOf: outputArray.compactMap { output in
                if let text = output.text, !text.isEmpty {
                    return text
                }
                if let outputString = output.output, !outputString.isEmpty {
                    return outputString
                }
                if let logs = output.logs, !logs.isEmpty {
                    return logs
                }
                return nil
            })
        }

        return outputs
    }
}
