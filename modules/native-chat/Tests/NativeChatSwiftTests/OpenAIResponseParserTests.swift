import Foundation
import ChatPersistenceSwiftData
import ChatDomain
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAIResponseParserTests {
    @Test func parseUploadedFileIDReadsSuccessfulResponse() throws {
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

    @Test func parseFetchedResponseExtractsTextAndStatus() throws {
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

    @Test func parseFetchedResponseExtractsCitationsAndAnnotations() throws {
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

    @Test func parseFetchedResponseExtractsToolCalls() throws {
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

    @Test func parseGeneratedTitleFallsBackWhenTextMissing() throws {
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

    @Test func parseGeneratedTitleTrimsQuotesAndLimitsToFiveWords() throws {
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

    @Test func parseGeneratedTitleFallsBackOnBadData() throws {
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

    @Test func parseGeneratedTitleThrowsOnBadResponse() throws {
        let parser = OpenAIResponseParser()
        let failureResponse = try makeHTTPResponse(
            url: "https://example.com/responses",
            statusCode: 503
        )

        do {
            _ = try parser.parseGeneratedTitle(data: Data(), response: failureResponse)
            Issue.record("Expected requestFailed error")
        } catch {
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Title generation failed")
        }
    }

    @Test func parseFetchedResponseThrowsHTTPErrorForFailureResponse() throws {
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
            guard case OpenAIServiceError.httpError(let statusCode, let message) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(statusCode == 429)
            #expect(message == #"{"error":"rate_limited"}"#)
        }
    }

    @Test func parseFetchedResponseRejectsInvalidResponse() throws {
        let parser = OpenAIResponseParser()

        do {
            _ = try parser.parseFetchedResponse(
                data: Data(),
                response: URLResponse()
            )
            Issue.record("Expected requestFailed error")
        } catch {
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Invalid response")
        }
    }

    @Test func parseFetchedResponseRejectsMalformedPayload() throws {
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
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Failed to parse response")
        }
    }
}
