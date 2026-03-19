// swiftlint:disable file_length
import ChatPersistenceSwiftData
import ChatDomain
import OpenAITransport
import XCTest
@testable import NativeChatComposition

// swiftlint:disable:next type_body_length
final class OpenAIResponseParserTests: XCTestCase {
    func testParseUploadedFileIDReadsSuccessfulResponse() throws {
        let parser = OpenAIResponseParser()
        let data = try JSONCoding.encode(UploadedFileResponseDTO(id: "file_123"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
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

    // swiftlint:disable:next function_body_length
    func testParseFetchedResponseExtractsStructuredFields() throws {
        let parser = OpenAIResponseParser()
        let outputText = "sandbox:/mnt/data/chart.png"

        let payload = ResponsesResponseDTO(
            status: "completed",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    id: nil,
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: outputText,
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
                                    endIndex: outputText.count,
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
                ),
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
                ),
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
                ),
                ResponsesOutputItemDTO(
                    type: "code_interpreter_call",
                    id: "ci_1",
                    content: nil,
                    action: nil,
                    query: nil,
                    queries: nil,
                    code: "print(1)",
                    results: [ResponsesCodeInterpreterOutputDTO(output: "1", text: nil, logs: nil)],
                    outputs: nil,
                    text: nil,
                    summary: nil
                ),
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
            ],
            error: ResponsesErrorDTO(message: "Some warning")
        )

        let data = try JSONCoding.encode(payload)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
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
        let data = try JSONCoding.encode(ResponsesResponseDTO(output: []))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
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

    func testParseGeneratedTitleTrimsQuotesAndLimitsToFiveWords() throws {
        let parser = OpenAIResponseParser()
        let data = try JSONCoding.encode(
            ResponsesResponseDTO(
                output: [
                    ResponsesOutputItemDTO(
                        type: "message",
                        id: nil,
                        content: [
                            ResponsesContentPartDTO(
                                type: "output_text",
                                text: "\"One two three four five six\"",
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
                ]
            )
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertEqual(
            try parser.parseGeneratedTitle(data: data, response: response),
            "One two three four five"
        )
    }

    func testParseGeneratedTitleFallsBackWhenDecodingFailsAndThrowsOnBadResponse() throws {
        let parser = OpenAIResponseParser()
        let successResponse = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let failureResponse = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses")!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertEqual(
            try parser.parseGeneratedTitle(data: Data("not-json".utf8), response: successResponse),
            "New Chat"
        )

        XCTAssertThrowsError(
            try parser.parseGeneratedTitle(data: Data(), response: failureResponse)
        ) { error in
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(message, "Title generation failed")
        }
    }

    func testParseFetchedResponseThrowsHTTPErrorForFailureResponse() throws {
        let parser = OpenAIResponseParser()
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses/resp_123")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertThrowsError(
            try parser.parseFetchedResponse(
                data: Data("{\"error\":\"rate_limited\"}".utf8),
                response: response
            )
        ) { error in
            guard case OpenAIServiceError.httpError(let statusCode, let message) = error else {
                return XCTFail("Expected httpError, got \(error)")
            }
            XCTAssertEqual(statusCode, 429)
            XCTAssertEqual(message, #"{"error":"rate_limited"}"#)
        }
    }

    func testParseFetchedResponseRejectsInvalidResponseAndMalformedPayload() throws {
        let parser = OpenAIResponseParser()

        XCTAssertThrowsError(
            try parser.parseFetchedResponse(
                data: Data(),
                response: URLResponse()
            )
        ) { error in
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(message, "Invalid response")
        }

        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses/resp_bad")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertThrowsError(
            try parser.parseFetchedResponse(
                data: Data("not-json".utf8),
                response: response
            )
        ) { error in
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(message, "Failed to parse response")
        }
    }

    // swiftlint:disable:next function_body_length
    func testParseFetchedResponseUsesActionQueriesAndOutputFallbacks() throws {
        let parser = OpenAIResponseParser()
        let payload = ResponsesResponseDTO(
            status: "in_progress",
            output: [
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
                ),
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
                ),
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
                        ResponsesCodeInterpreterOutputDTO(output: nil, text: "", logs: "log line"),
                        ResponsesCodeInterpreterOutputDTO(output: nil, text: "2", logs: nil)
                    ],
                    text: nil,
                    summary: nil
                ),
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
            ],
            reasoning: ResponsesReasoningDTO(
                text: "analysis",
                summary: [ResponsesTextFragmentDTO(text: " complete")]
            ),
            message: "still working"
        )
        let data = try JSONCoding.encode(payload)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses/resp_456")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        XCTAssertEqual(result.status, .inProgress)
        XCTAssertEqual(result.text, "Primary response")
        XCTAssertEqual(result.thinking, "analysis complete")
        XCTAssertEqual(result.errorMessage, "still working")
        XCTAssertEqual(result.toolCalls.count, 3)
        XCTAssertEqual(result.toolCalls[0].queries, ["swift", "ios"])
        XCTAssertEqual(result.toolCalls[1].code, "print(2)")
        XCTAssertEqual(result.toolCalls[1].results ?? [], ["log line", "2"])
        XCTAssertEqual(result.toolCalls[2].queries, ["notes", "summary"])
    }

    func testParseUploadedFileIDThrowsRequestFailedWhenPayloadCannotBeDecoded() throws {
        let parser = OpenAIResponseParser()
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/files")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertThrowsError(
            try parser.parseUploadedFileID(
                responseData: Data("{}".utf8),
                response: response
            )
        ) { error in
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(message, "Failed to parse upload response")
        }
    }

    func testParseUploadedFileIDRejectsNonHTTPResponseAndHTTPFailures() throws {
        let parser = OpenAIResponseParser()

        XCTAssertThrowsError(
            try parser.parseUploadedFileID(
                responseData: Data(),
                response: URLResponse()
            )
        ) { error in
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(message, "Invalid response")
        }

        // swiftlint:disable:next force_try
        let response = try! XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/files")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertThrowsError(
            try parser.parseUploadedFileID(
                responseData: Data("upload-failed".utf8),
                response: response
            )
        ) { error in
            guard case OpenAIServiceError.httpError(let statusCode, let message) = error else {
                return XCTFail("Expected httpError, got \(error)")
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "upload-failed")
        }
    }

    func testResponsesErrorDTODecodesStringAndObjectPayloads() throws {
        XCTAssertEqual(
            try JSONCoding.decode(ResponsesErrorDTO.self, from: Data(#""plain failure""#.utf8)),
            ResponsesErrorDTO(message: "plain failure")
        )
        XCTAssertEqual(
            try JSONCoding.decode(ResponsesErrorDTO.self, from: Data(#"{"message":"structured failure"}"#.utf8)),
            ResponsesErrorDTO(message: "structured failure")
        )
    }

    func testResponsesStreamEnvelopeResolvesSequenceAndErrorFromTopLevelFields() throws {
        let envelope = try JSONCoding.decode(
            ResponsesStreamEnvelopeDTO.self,
            from: Data(#"{"sequence_number":17,"message":"stream failed"}"#.utf8)
        )

        XCTAssertEqual(envelope.sequenceNumber, 17)
        XCTAssertEqual(envelope.resolvedResponse.sequenceNumber, 17)
        XCTAssertEqual(envelope.resolvedResponse.message, "stream failed")
    }

    func testOpenAIServiceErrorDescriptionsMatchBehavior() {
        XCTAssertEqual(OpenAIServiceError.noAPIKey.errorDescription, "No API key configured. Please add it in Settings.")
        XCTAssertEqual(OpenAIServiceError.invalidURL.errorDescription, "Invalid API URL.")
        XCTAssertEqual(OpenAIServiceError.httpError(500, "oops").errorDescription, "API error (500): oops")
        XCTAssertEqual(OpenAIServiceError.requestFailed("broken").errorDescription, "broken")
        XCTAssertEqual(OpenAIServiceError.cancelled.errorDescription, "Request was cancelled.")
    }

    // swiftlint:disable:next function_body_length
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

        let digest = MessagePayloadStore.renderDigest(for: message)

        let reconstructed = Message(role: .assistant, content: "initial")
        reconstructed.annotationsData = message.annotationsData
        reconstructed.toolCallsData = message.toolCallsData
        reconstructed.filePathAnnotationsData = message.filePathAnnotationsData
        reconstructed.fileAttachmentsData = message.fileAttachmentsData

        XCTAssertEqual(MessagePayloadStore.renderDigest(for: reconstructed), digest)
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

        let message = Message(role: .assistant, content: "hello")
        MessagePayloadStore.setAnnotations(annotations, on: message)
        MessagePayloadStore.setToolCalls(toolCalls, on: message)
        MessagePayloadStore.setFileAttachments(fileAttachments, on: message)
        MessagePayloadStore.setFilePathAnnotations([], on: message)

        let baselineDigest = MessagePayloadStore.renderDigest(for: message)
        MessagePayloadStore.setFilePathAnnotations(
            [
                FilePathAnnotation(
                    fileId: "attachment-id",
                    containerId: "container-1",
                    sandboxPath: "/workspace/sample.pdf",
                    filename: "sample.pdf",
                    startIndex: 0,
                    endIndex: 11
                )
            ],
            on: message
        )

        XCTAssertNotEqual(MessagePayloadStore.renderDigest(for: message), baselineDigest)
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
