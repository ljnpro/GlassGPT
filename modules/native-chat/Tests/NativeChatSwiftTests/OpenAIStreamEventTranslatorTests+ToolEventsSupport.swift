import ChatDomain
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

// MARK: - Private Fixture Builders

extension OpenAIStreamEventTranslatorTests {
    func makeTerminalResponse() -> ResponsesResponseDTO {
        let fileAnnotation = ResponsesAnnotationDTO(
            type: "file_path",
            url: nil,
            title: nil,
            startIndex: 0,
            endIndex: 13,
            fileID: "file_terminal",
            containerID: "container_1",
            filename: "report.txt"
        )
        return ResponsesResponseDTO(
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    id: nil,
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "sandbox:/tmp/report.txt",
                            annotations: [fileAnnotation]
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
            ],
            reasoning: ResponsesReasoningDTO(
                text: "plan",
                summary: [ResponsesTextFragmentDTO(text: " summary")]
            ),
            message: "needs recovery"
        )
    }

    func makeStructuredExtractionResponse() -> ResponsesResponseDTO {
        ResponsesResponseDTO(
            outputText: "top level text",
            output: [
                makeStructuredMessageOutput(),
                makeStructuredReasoningOutput()
            ],
            reasoning: ResponsesReasoningDTO(
                text: "top",
                summary: [ResponsesTextFragmentDTO(text: " level")]
            ),
            error: ResponsesErrorDTO(message: "structured")
        )
    }

    private func makeStructuredMessageOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "message",
            id: nil,
            content: [
                ResponsesContentPartDTO(
                    type: "output_text",
                    text: "body",
                    annotations: [
                        ResponsesAnnotationDTO(
                            type: "file_path",
                            url: nil,
                            title: nil,
                            startIndex: 0,
                            endIndex: 999,
                            fileID: "file_1",
                            containerID: nil,
                            filename: "body.txt"
                        ),
                        ResponsesAnnotationDTO(
                            type: "file_path",
                            url: nil,
                            title: nil,
                            startIndex: 0,
                            endIndex: 3,
                            fileID: nil,
                            containerID: nil,
                            filename: nil
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

    private func makeStructuredReasoningOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "reasoning",
            id: nil,
            content: [
                ResponsesContentPartDTO(type: "output_text", text: " step", annotations: nil)
            ],
            action: nil,
            query: nil,
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: "plan",
            summary: [ResponsesTextFragmentDTO(text: " summary")]
        )
    }
}
