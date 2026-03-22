import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

extension OpenAIResponseParserTests {
    func makeActionQueriesPayload() -> ResponsesResponseDTO {
        ResponsesResponseDTO(
            status: "in_progress",
            output: [
                makeActionMessageOutput(),
                makeActionWebSearchOutput(),
                makeActionCodeInterpreterOutput(),
                makeActionFileSearchOutput()
            ],
            reasoning: ResponsesReasoningDTO(
                text: "analysis",
                summary: [ResponsesTextFragmentDTO(text: " complete")]
            ),
            message: "still working"
        )
    }

    private func makeActionMessageOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "message",
            id: nil,
            content: [
                ResponsesContentPartDTO(
                    type: "output_text",
                    text: "Primary response",
                    annotations: nil
                ),
                ResponsesContentPartDTO(
                    type: "input_text",
                    text: "ignored",
                    annotations: nil
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

    private func makeActionWebSearchOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "web_search_call",
            id: "ws_action",
            content: nil,
            action: ResponsesActionDTO(query: nil, queries: ["swift", "ios"]),
            query: nil,
            queries: nil,
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    private func makeActionCodeInterpreterOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "code_interpreter_call",
            id: "ci_outputs",
            content: nil,
            action: nil,
            query: nil,
            queries: nil,
            code: "print(2)",
            results: nil,
            outputs: [
                ResponsesCodeInterpreterOutputDTO(
                    output: nil,
                    text: "",
                    logs: "log line"
                ),
                ResponsesCodeInterpreterOutputDTO(
                    output: nil,
                    text: "2",
                    logs: nil
                )
            ],
            text: nil,
            summary: nil
        )
    }

    private func makeActionFileSearchOutput() -> ResponsesOutputItemDTO {
        ResponsesOutputItemDTO(
            type: "file_search_call",
            id: "fs_queries",
            content: nil,
            action: nil,
            query: nil,
            queries: ["notes", "summary"],
            code: nil,
            results: nil,
            outputs: nil,
            text: nil,
            summary: nil
        )
    }

    func makeTestCitations() -> [URLCitation] {
        [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            ),
            URLCitation(
                url: "https://example.org",
                title: "Second",
                startIndex: 10,
                endIndex: 20
            )
        ]
    }

    func makeTestToolCalls() -> [ToolCallInfo] {
        [
            ToolCallInfo(
                id: "tc_1",
                type: .webSearch,
                status: .completed,
                code: nil,
                results: nil,
                queries: ["swift"]
            ),
            ToolCallInfo(
                id: "tc_2",
                type: .codeInterpreter,
                status: .completed,
                code: "print(1)",
                results: ["1"],
                queries: nil
            )
        ]
    }

    func makeTestFilePathAnnotations() -> [FilePathAnnotation] {
        [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "sandbox:/mnt/data/report.txt",
                filename: "report.txt",
                startIndex: 0,
                endIndex: 20
            )
        ]
    }

    func makeTestFileAttachments() -> [FileAttachment] {
        [
            FileAttachment(
                id: UUID(),
                filename: "sample.pdf",
                fileSize: 128,
                fileType: "pdf",
                fileId: "file_attachment_1",
                uploadStatus: .uploaded
            )
        ]
    }
}

struct FailingDigestPayload: Encodable {
    func encode(to _: Encoder) throws {
        throw EncodingError.invalidValue(
            "boom",
            .init(codingPath: [], debugDescription: "intentional test failure")
        )
    }
}

struct FailingPayload: PayloadCodable {
    func encode(to _: Encoder) throws {
        throw EncodingError.invalidValue(
            "boom",
            .init(codingPath: [], debugDescription: "intentional payload failure")
        )
    }

    init() {}

    init(from _: Decoder) throws {
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "intentional payload decode failure")
        )
    }
}
