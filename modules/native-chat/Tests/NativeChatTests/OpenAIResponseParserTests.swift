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
}
