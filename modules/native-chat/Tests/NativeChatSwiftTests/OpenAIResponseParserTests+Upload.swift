import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

// MARK: - Upload and Error Parsing Tests

extension OpenAIResponseParserTests {
    @Test func parseUploadedFileIDThrowsRequestFailedWhenPayloadCannotBeDecoded() throws {
        let parser = OpenAIResponseParser()
        let response = try makeHTTPResponse(
            url: "https://example.com/files",
            statusCode: 200
        )

        do {
            _ = try parser.parseUploadedFileID(
                responseData: Data("{}".utf8),
                response: response
            )
            Issue.record("Expected requestFailed error")
        } catch {
            guard case OpenAIServiceError.requestFailed(let message) = error else {
                Issue.record("Expected requestFailed, got \(error)")
                return
            }
            #expect(message == "Failed to parse upload response")
        }
    }

    @Test func parseUploadedFileIDRejectsNonHTTPResponse() throws {
        let parser = OpenAIResponseParser()

        do {
            _ = try parser.parseUploadedFileID(
                responseData: Data(),
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

    @Test func parseUploadedFileIDRejectsHTTPFailures() throws {
        let parser = OpenAIResponseParser()
        let response = try makeHTTPResponse(
            url: "https://example.com/files",
            statusCode: 500
        )

        do {
            _ = try parser.parseUploadedFileID(
                responseData: Data("upload-failed".utf8),
                response: response
            )
            Issue.record("Expected httpError")
        } catch {
            guard case OpenAIServiceError.httpError(let statusCode, let message) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(statusCode == 500)
            #expect(message == "upload-failed")
        }
    }

    @Test func responsesErrorDTODecodesStringAndObjectPayloads() throws {
        #expect(
            try JSONCoding.decode(ResponsesErrorDTO.self, from: Data(#""plain failure""#.utf8))
                == ResponsesErrorDTO(message: "plain failure")
        )
        #expect(
            try JSONCoding.decode(
                ResponsesErrorDTO.self,
                from: Data(#"{"message":"structured failure"}"#.utf8)
            ) == ResponsesErrorDTO(message: "structured failure")
        )
    }

    @Test func responsesStreamEnvelopeResolvesSequenceAndErrorFromTopLevelFields() throws {
        let envelope = try JSONCoding.decode(
            ResponsesStreamEnvelopeDTO.self,
            from: Data(#"{"sequence_number":17,"message":"stream failed"}"#.utf8)
        )

        #expect(envelope.sequenceNumber == 17)
        #expect(envelope.resolvedResponse.sequenceNumber == 17)
        #expect(envelope.resolvedResponse.message == "stream failed")
    }

    @Test func openAIServiceErrorDescriptionsMatchBehavior() {
        #expect(
            OpenAIServiceError.noAPIKey.errorDescription
                == "No API key configured. Please add it in Settings."
        )
        #expect(OpenAIServiceError.invalidURL.errorDescription == "Invalid API URL.")
        #expect(OpenAIServiceError.httpError(500, "oops").errorDescription == "API error (500): oops")
        #expect(OpenAIServiceError.requestFailed("broken").errorDescription == "broken")
        #expect(OpenAIServiceError.cancelled.errorDescription == "Request was cancelled.")
    }
}
