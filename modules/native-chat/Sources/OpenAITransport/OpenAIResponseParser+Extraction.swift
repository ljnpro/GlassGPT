import ChatDomain
import Foundation

extension OpenAIResponseParser {
    public static func extractCitations(from response: ResponsesResponseDTO) -> [URLCitation] {
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

                    annotations.append(
                        URLCitation(
                            url: url,
                            title: title,
                            startIndex: ann.startIndex ?? 0,
                            endIndex: ann.endIndex ?? 0
                        )
                    )
                }
            }
        }

        return annotations
    }

    public static func extractToolCalls(from response: ResponsesResponseDTO) -> [ToolCallInfo] {
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

                toolCalls.append(
                    ToolCallInfo(
                        id: callId,
                        type: .webSearch,
                        status: .completed,
                        queries: queries
                    )
                )

            case "code_interpreter_call":
                let code = item.code
                let results = extractCodeInterpreterOutputs(from: item)

                toolCalls.append(
                    ToolCallInfo(
                        id: callId,
                        type: .codeInterpreter,
                        status: .completed,
                        code: code,
                        results: results.isEmpty ? nil : results
                    )
                )

            case "file_search_call":
                var queries: [String]? = nil

                if let query = item.query {
                    queries = [query]
                } else if let queryList = item.queries {
                    queries = queryList
                }

                toolCalls.append(
                    ToolCallInfo(
                        id: callId,
                        type: .fileSearch,
                        status: .completed,
                        queries: queries
                    )
                )

            default:
                continue
            }
        }

        return toolCalls
    }

    public static func extractCodeInterpreterOutputs(from item: ResponsesOutputItemDTO) -> [String] {
        var outputs: [String] = []

        if let resultArray = item.results {
            outputs.append(
                contentsOf: resultArray.compactMap { result in
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
                }
            )
        }

        if let outputArray = item.outputs {
            outputs.append(
                contentsOf: outputArray.compactMap { output in
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
                }
            )
        }

        return outputs
    }
}
