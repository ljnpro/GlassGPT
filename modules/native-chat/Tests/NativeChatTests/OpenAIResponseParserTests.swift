import XCTest
@testable import NativeChat

final class OpenAIResponseParserTests: XCTestCase {
    func testParseUploadedFileIDReadsSuccessfulResponse() throws {
        let parser = OpenAIResponseParser()
        let data = try JSONSerialization.data(withJSONObject: ["id": "file_123"])
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/files")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertEqual(
            try parser.parseUploadedFileID(responseData: data, response: response),
            "file_123"
        )
    }

    func testParseFetchedResponseExtractsStructuredFields() throws {
        let parser = OpenAIResponseParser()
        let outputText = "sandbox:/mnt/data/chart.png"

        let payload: [String: Any] = [
            "status": "completed",
            "error": ["message": "Some warning"],
            "output": [
                [
                    "type": "message",
                    "content": [[
                        "type": "output_text",
                        "text": outputText,
                        "annotations": [
                            [
                                "type": "url_citation",
                                "url": "https://example.com",
                                "title": "Example",
                                "start_index": 0,
                                "end_index": 7
                            ],
                            [
                                "type": "file_path",
                                "file_id": "file_chart",
                                "container_id": "container_123",
                                "filename": "chart.png",
                                "start_index": 0,
                                "end_index": outputText.count
                            ]
                        ]
                    ]]
                ],
                [
                    "type": "reasoning",
                    "summary": [["text": "Reasoning summary"]]
                ],
                [
                    "type": "web_search_call",
                    "id": "ws_1",
                    "query": "glassgpt"
                ],
                [
                    "type": "code_interpreter_call",
                    "id": "ci_1",
                    "code": "print(1)",
                    "results": [["output": "1"]]
                ],
                [
                    "type": "file_search_call",
                    "id": "fs_1",
                    "query": "notes"
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/responses/resp_123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.text, outputText)
        XCTAssertEqual(result.thinking, "Reasoning summary")
        XCTAssertEqual(result.annotations, [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            )
        ])
        XCTAssertEqual(result.toolCalls.count, 3)
        XCTAssertEqual(result.toolCalls[0].type, .webSearch)
        XCTAssertEqual(result.toolCalls[0].queries, ["glassgpt"])
        XCTAssertEqual(result.toolCalls[1].type, .codeInterpreter)
        XCTAssertEqual(result.toolCalls[1].code, "print(1)")
        XCTAssertEqual(result.toolCalls[1].results, ["1"])
        XCTAssertEqual(result.toolCalls[2].type, .fileSearch)
        XCTAssertEqual(result.filePathAnnotations, [
            FilePathAnnotation(
                fileId: "file_chart",
                containerId: "container_123",
                sandboxPath: outputText,
                filename: "chart.png",
                startIndex: 0,
                endIndex: outputText.count
            )
        ])
        XCTAssertEqual(result.errorMessage, "Some warning")
    }

    func testParseGeneratedTitleFallsBackWhenTextMissing() throws {
        let parser = OpenAIResponseParser()
        let data = try JSONSerialization.data(withJSONObject: ["output": []])
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/responses")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertEqual(
            try parser.parseGeneratedTitle(data: data, response: response),
            "New Chat"
        )
    }

    func testOpenAIServiceErrorDescriptionsMatchBehavior() {
        XCTAssertEqual(OpenAIServiceError.noAPIKey.errorDescription, "No API key configured. Please add it in Settings.")
        XCTAssertEqual(OpenAIServiceError.invalidURL.errorDescription, "Invalid API URL.")
        XCTAssertEqual(OpenAIServiceError.httpError(500, "oops").errorDescription, "API error (500): oops")
        XCTAssertEqual(OpenAIServiceError.requestFailed("broken").errorDescription, "broken")
        XCTAssertEqual(OpenAIServiceError.cancelled.errorDescription, "Request was cancelled.")
    }

    func testPayloadStoreRoundTripsBetweenMessageAndRenderDigest() {
        let citations = [
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

        let toolCalls = [
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

        let filePathAnnotations = [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "sandbox:/mnt/data/report.txt",
                filename: "report.txt",
                startIndex: 0,
                endIndex: 20
            )
        ]

        let fileAttachments = [
            FileAttachment(
                id: UUID(),
                filename: "sample.pdf",
                fileSize: 128,
                fileType: "pdf",
                fileId: "file_attachment_1",
                uploadStatus: .uploaded
            )
        ]

        let message = Message(role: .assistant, content: "initial")
        MessagePayloadStore.setAnnotations(citations, on: message)
        MessagePayloadStore.setToolCalls(toolCalls, on: message)
        MessagePayloadStore.setFilePathAnnotations(filePathAnnotations, on: message)
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)

        XCTAssertEqual(message.annotations, citations)
        XCTAssertEqual(message.toolCalls, toolCalls)
        XCTAssertEqual(message.filePathAnnotations, filePathAnnotations)
        XCTAssertEqual(message.fileAttachments.count, 1)
        XCTAssertEqual(message.fileAttachments.first?.id, fileAttachments.first?.id)
        XCTAssertEqual(message.fileAttachments.first?.filename, fileAttachments.first?.filename)
        XCTAssertEqual(message.fileAttachments.first?.fileSize, fileAttachments.first?.fileSize)
        XCTAssertEqual(message.fileAttachments.first?.fileType, fileAttachments.first?.fileType)
        XCTAssertEqual(message.fileAttachments.first?.openAIFileId, fileAttachments.first?.openAIFileId)

        let digest = message.payloadRenderDigest

        let reconstructed = Message(role: .assistant, content: "initial")
        reconstructed.annotationsData = message.annotationsData
        reconstructed.toolCallsData = message.toolCallsData
        reconstructed.filePathAnnotationsData = message.filePathAnnotationsData
        reconstructed.fileAttachmentsData = message.fileAttachmentsData

        XCTAssertEqual(reconstructed.payloadRenderDigest, digest)
        XCTAssertEqual(reconstructed.annotations, citations)
        XCTAssertEqual(reconstructed.toolCalls, toolCalls)
        XCTAssertEqual(reconstructed.filePathAnnotations, filePathAnnotations)
        XCTAssertEqual(reconstructed.fileAttachments.count, 1)
        XCTAssertEqual(reconstructed.fileAttachments.first?.id, fileAttachments.first?.id)
        XCTAssertEqual(reconstructed.fileAttachments.first?.filename, fileAttachments.first?.filename)
        XCTAssertEqual(reconstructed.fileAttachments.first?.fileSize, fileAttachments.first?.fileSize)
        XCTAssertEqual(reconstructed.fileAttachments.first?.fileType, fileAttachments.first?.fileType)
        XCTAssertEqual(reconstructed.fileAttachments.first?.openAIFileId, fileAttachments.first?.openAIFileId)
    }

    func testRenderDigestMatchesExplicitPayloadComponents() {
        let annotations = [
            URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)
        ]
        let toolCalls = [
            ToolCallInfo(id: "tc", type: .fileSearch, status: .completed, code: nil, results: nil, queries: ["a"])
        ]
        let fileAttachments = [
            FileAttachment(
                id: UUID(),
                filename: "sample.pdf",
                fileSize: 128,
                fileType: "pdf",
                fileId: "attachment-id",
                uploadStatus: .uploaded
            )
        ]

        let directDigest = MessagePayloadStore.renderDigest(
            annotations: annotations,
            toolCalls: toolCalls,
            fileAttachments: fileAttachments,
            filePathAnnotations: []
        )

        let message = Message(role: .assistant, content: "hello")
        MessagePayloadStore.setAnnotations(annotations, on: message)
        MessagePayloadStore.setToolCalls(toolCalls, on: message)
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)

        XCTAssertEqual(message.payloadRenderDigest, directDigest)
    }

    func testInvalidPayloadDataFallsBackToEmptyCollections() {
        let invalid = Data("not-json".utf8)

        XCTAssertTrue(MessagePayloadStore.annotations(from: invalid).isEmpty)
        XCTAssertTrue(MessagePayloadStore.toolCalls(from: invalid).isEmpty)
        XCTAssertTrue(MessagePayloadStore.fileAttachments(from: invalid).isEmpty)
        XCTAssertTrue(MessagePayloadStore.filePathAnnotations(from: invalid).isEmpty)
    }

    func testSetEmptyPayloadStoresNilDataAndStabilizesDigest() {
        let message = Message(role: .assistant, content: "hello")

        MessagePayloadStore.setAnnotations([], on: message)
        MessagePayloadStore.setToolCalls([], on: message)
        MessagePayloadStore.setFileAttachments([], on: message)
        MessagePayloadStore.setFilePathAnnotations([], on: message)

        XCTAssertNil(message.annotationsData)
        XCTAssertNil(message.toolCallsData)
        XCTAssertNil(message.fileAttachmentsData)
        XCTAssertNil(message.filePathAnnotationsData)
        XCTAssertEqual(message.payloadRenderDigest, MessagePayloadStore.renderDigest(
            annotations: [],
            toolCalls: [],
            fileAttachments: [],
            filePathAnnotations: []
        ))
    }
}
