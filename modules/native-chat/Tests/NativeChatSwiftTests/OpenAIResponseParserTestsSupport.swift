import ChatDomain
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

// MARK: - Helpers and Fixture Builders

extension OpenAIResponseParserTests {
    func makeHTTPResponse(url: String, statusCode: Int) throws -> HTTPURLResponse {
        let parsedURL = try #require(URL(string: url))
        return try #require(
            HTTPURLResponse(
                url: parsedURL,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }

    func makeStructuredPayload() -> ResponsesResponseDTO {
        let outputText = "sandbox:/mnt/data/chart.png"
        return ResponsesResponseDTO(
            status: "completed",
            output: [
                makeMessageOutput(text: outputText),
                makeReasoningOutput(),
                makeWebSearchOutput(),
                makeCodeInterpreterOutput(),
                makeFileSearchOutput()
            ],
            error: ResponsesErrorDTO(message: "Some warning")
        )
    }

    private func makeMessageOutput(text: String) -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "message",
            id: nil,
            content: [
                ResponsesContentPartDTO(
                    type: "output_text",
                    text: text,
                    annotations: [
                        ResponsesAnnotationDTO(
                            type: "url_citation",
                            url: "https://example.com",
                            title: "Example",
                            startIndex: 0,
                            endIndex: 7,
                            fileID: nil,
                            containerID: nil,
                            filename: nil
                        ),
                        ResponsesAnnotationDTO(
                            type: "file_path",
                            url: nil,
                            title: nil,
                            startIndex: 0,
                            endIndex: text.count,
                            fileID: "file_chart",
                            containerID: "container_123",
                            filename: "chart.png"
                        )
                    ]
                )
            ],
            action: nil,
            query: nil,
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    private func makeReasoningOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "reasoning",
            id: nil,
            content: nil,
            action: nil,
            query: nil,
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: [ResponsesTextFragmentDTO(text: "Reasoning summary")]
        )
    }

    private func makeWebSearchOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "web_search_call",
            id: "ws_1",
            content: nil,
            action: nil,
            query: "glassgpt",
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    private func makeCodeInterpreterOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "code_interpreter_call",
            id: "ci_1",
            content: nil,
            action: nil,
            query: nil,
            queries: nil,
            code: "print(1)",
            results: [
                ResponsesCodeInterpreterOutputDTO(output: "1", text: nil, logs: nil)
            ],
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    private func makeFileSearchOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "file_search_call",
            id: "fs_1",
            content: nil,
            action: nil,
            query: "notes",
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }
}
