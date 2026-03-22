import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

extension OpenAIResponseParserTests {
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
