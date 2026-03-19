import Foundation
import OpenAITransport
import Testing

// MARK: - Fixture Builders

extension SourceTargetBoundaryTests {
    func makeStreamRequest() -> ResponsesStreamRequestDTO {
        ResponsesStreamRequestDTO(
            model: "gpt-5.4",
            input: [
                ResponsesInputMessageDTO(
                    role: "user",
                    content: .items([
                        .inputText("Hello"),
                        .inputFile("file_123")
                    ])
                )
            ],
            stream: true,
            store: true,
            serviceTier: "default",
            tools: [
                ResponsesToolDTO(type: "web_search_preview"),
                ResponsesToolDTO(type: "code_interpreter", container: .init(type: "auto"))
            ],
            background: true,
            reasoning: ResponsesReasoningRequestDTO(effort: "high", summary: "auto")
        )
    }

    func makeResponsePayload() -> ResponsesResponseDTO {
        ResponsesResponseDTO(
            id: "resp_123",
            status: "completed",
            sequenceNumber: 8,
            outputText: "Done",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "Done",
                            annotations: [
                                ResponsesAnnotationDTO(
                                    type: "url_citation",
                                    url: "https://example.com",
                                    title: "Example",
                                    startIndex: 0,
                                    endIndex: 4
                                )
                            ]
                        )
                    ]
                )
            ],
            reasoning: ResponsesReasoningDTO(
                text: "thinking",
                summary: [ResponsesTextFragmentDTO(text: "summary")]
            ),
            error: nil,
            message: nil
        )
    }

    func makeParserPayload() -> ResponsesResponseDTO {
        ResponsesResponseDTO(
            status: "completed",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "sandbox:/tmp/report.txt",
                            annotations: [
                                ResponsesAnnotationDTO(
                                    type: "file_path",
                                    startIndex: 0,
                                    endIndex: 23,
                                    fileID: "file_report",
                                    containerID: "container_123",
                                    filename: "report.txt"
                                )
                            ]
                        )
                    ]
                )
            ],
            reasoning: ResponsesReasoningDTO(text: "thinking", summary: nil)
        )
    }
}
