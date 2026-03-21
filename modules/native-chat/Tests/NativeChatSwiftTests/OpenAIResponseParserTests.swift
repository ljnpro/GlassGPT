import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAIResponseParserTests {
    @Test func `parse uploaded file ID reads successful response`() throws {
        let parser = OpenAIResponseParser()
        let data = try JSONCoding.encode(UploadedFileResponseDTO(id: "file_123"))
        let fileURL = try #require(URL(string: "https://example.com/files"))
        let response = try #require(
            HTTPURLResponse(
                url: fileURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        #expect(
            try parser.parseUploadedFileID(responseData: data, response: response)
                == "file_123"
        )
    }

    @Test func `parse fetched response extracts text and status`() throws {
        let parser = OpenAIResponseParser()
        let payload = makeStructuredPayload()
        let data = try JSONCoding.encode(payload)
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_123",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.status == .completed)
        #expect(result.text == "sandbox:/mnt/data/chart.png")
        #expect(result.thinking == "Reasoning summary")
        #expect(result.errorMessage == "Some warning")
    }

    @Test func `parse fetched response extracts citations and annotations`() throws {
        let parser = OpenAIResponseParser()
        let payload = makeStructuredPayload()
        let data = try JSONCoding.encode(payload)
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_123",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.annotations == [
            URLCitation(
                url: "https://example.com",
                title: "Example",
                startIndex: 0,
                endIndex: 7
            )
        ])
        #expect(result.filePathAnnotations == [
            FilePathAnnotation(
                fileId: "file_chart",
                containerId: "container_123",
                sandboxPath: "sandbox:/mnt/data/chart.png",
                filename: "chart.png",
                startIndex: 0,
                endIndex: 27
            )
        ])
    }

    @Test func `parse fetched response extracts tool calls`() throws {
        let parser = OpenAIResponseParser()
        let payload = makeStructuredPayload()
        let data = try JSONCoding.encode(payload)
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_123",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.toolCalls.count == 3)
        #expect(result.toolCalls[0].type == .webSearch)
        #expect(result.toolCalls[0].queries == ["glassgpt"])
        #expect(result.toolCalls[1].type == .codeInterpreter)
        #expect(result.toolCalls[1].code == "print(1)")
        #expect(result.toolCalls[1].results == ["1"])
        #expect(result.toolCalls[2].type == .fileSearch)
    }

    @Test func `parse fetched response accepts string reasoning summary mode from live payloads`() throws {
        let parser = OpenAIResponseParser()
        let data = Data(
            #"""
            {
              "id": "resp_live_payload",
              "status": "completed",
              "reasoning": {
                "effort": "xhigh",
                "summary": "detailed"
              },
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "Hi! How can I help?",
                      "annotations": []
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_live_payload",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.status == .completed)
        #expect(result.text == "Hi! How can I help?")
        #expect(result.thinking == nil)
    }

    @Test func `parse fetched response accepts string reasoning summary on output item`() throws {
        let parser = OpenAIResponseParser()
        let data = Data(
            #"""
            {
              "id": "resp_nested_summary",
              "status": "completed",
              "output": [
                {
                  "type": "reasoning",
                  "summary": "detailed"
                },
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "Hi! How can I help?",
                      "annotations": []
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_nested_summary",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.status == .completed)
        #expect(result.text == "Hi! How can I help?")
        #expect(result.thinking == nil)
    }

    @Test func `parse fetched response extracts live xhigh greeting reasoning summary and answer`() throws {
        let parser = OpenAIResponseParser()
        let data = Data(
            #"""
            {
              "id": "resp_xhigh_hi",
              "status": "completed",
              "output": [
                {
                  "id": "rs_xhigh_hi",
                  "type": "reasoning",
                  "summary": [
                    {
                      "type": "summary_text",
                      "text": "**Preparing friendly response**"
                    }
                  ]
                },
                {
                  "id": "msg_xhigh_hi",
                  "type": "message",
                  "status": "completed",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "Hi! How can I help?",
                      "annotations": []
                    }
                  ],
                  "phase": "final_answer",
                  "role": "assistant"
                }
              ],
              "reasoning": {
                "effort": "xhigh",
                "summary": "detailed"
              }
            }
            """#.utf8
        )
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_xhigh_hi",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.status == .completed)
        #expect(result.text == "Hi! How can I help?")
        #expect(result.thinking == "**Preparing friendly response**")
    }

    @Test func `parse fetched response prefers final answer message over earlier assistant drafts`() throws {
        let parser = OpenAIResponseParser()
        let data = Data(
            #"""
            {
              "id": "resp_multi_message",
              "status": "completed",
              "output": [
                {
                  "id": "msg_draft_1",
                  "type": "message",
                  "role": "assistant",
                  "status": "completed",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "Hi! How can I help?",
                      "annotations": []
                    }
                  ]
                },
                {
                  "id": "msg_final",
                  "type": "message",
                  "role": "assistant",
                  "status": "completed",
                  "phase": "final_answer",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "Hello! What can I do for you today?",
                      "annotations": []
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_multi_message",
            statusCode: 200
        )

        let result = try parser.parseFetchedResponse(data: data, response: response)

        #expect(result.status == .completed)
        #expect(result.text == "Hello! What can I do for you today?")
    }

    @Test func `parse generated title falls back when text missing`() throws {
        let parser = OpenAIResponseParser()
        let data = try JSONCoding.encode(ResponsesResponseDTO(output: []))
        let response = try makeHTTPResponse(
            url: "https://example.com/responses",
            statusCode: 200
        )

        #expect(
            try parser.parseGeneratedTitle(data: data, response: response)
                == "New Chat"
        )
    }

    @Test func `parse generated title trims quotes and limits to five words`() throws {
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
        let response = try makeHTTPResponse(
            url: "https://example.com/responses",
            statusCode: 200
        )

        #expect(
            try parser.parseGeneratedTitle(data: data, response: response)
                == "One two three four five"
        )
    }

    @Test func `parse generated title falls back on bad data`() throws {
        let parser = OpenAIResponseParser()
        let successResponse = try makeHTTPResponse(
            url: "https://example.com/responses",
            statusCode: 200
        )

        #expect(
            try parser.parseGeneratedTitle(
                data: Data("not-json".utf8),
                response: successResponse
            ) == "New Chat"
        )
    }

    @Test func `parse generated title throws on bad response`() throws {
        let parser = OpenAIResponseParser()
        let failureResponse = try makeHTTPResponse(
            url: "https://example.com/responses",
            statusCode: 503
        )

        do {
            _ = try parser.parseGeneratedTitle(data: Data(), response: failureResponse)
            Issue.record("Expected requestFailed error")
        } catch {
            guard case let OpenAIServiceError.requestFailed(message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Title generation failed")
        }
    }

    @Test func `parse fetched response throws HTTP error for failure response`() throws {
        let parser = OpenAIResponseParser()
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_123",
            statusCode: 429
        )

        do {
            _ = try parser.parseFetchedResponse(
                data: Data("{\"error\":\"rate_limited\"}".utf8),
                response: response
            )
            Issue.record("Expected httpError")
        } catch {
            guard case let OpenAIServiceError.httpError(statusCode, message) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(statusCode == 429)
            #expect(message == #"{"error":"rate_limited"}"#)
        }
    }

    @Test func `parse fetched response rejects invalid response`() throws {
        let parser = OpenAIResponseParser()

        do {
            _ = try parser.parseFetchedResponse(
                data: Data(),
                response: URLResponse()
            )
            Issue.record("Expected requestFailed error")
        } catch {
            guard case let OpenAIServiceError.requestFailed(message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Invalid response")
        }
    }

    @Test func `parse fetched response rejects malformed payload`() throws {
        let parser = OpenAIResponseParser()
        let response = try makeHTTPResponse(
            url: "https://example.com/responses/resp_bad",
            statusCode: 200
        )

        do {
            _ = try parser.parseFetchedResponse(
                data: Data("not-json".utf8),
                response: response
            )
            Issue.record("Expected requestFailed error")
        } catch {
            guard case let OpenAIServiceError.requestFailed(message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Failed to parse response")
        }
    }
}
