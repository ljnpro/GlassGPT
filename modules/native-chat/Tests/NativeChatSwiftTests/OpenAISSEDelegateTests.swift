import Foundation
import Testing
@testable import OpenAITransport

struct OpenAISSEDelegateTests {
    @Test func `delegate converts generic HTTP failures into stream errors`() async throws {
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )
        let delegate = OpenAISSEDelegate(continuation: continuation.continuation)
        let url = try #require(URL(string: "https://api.openai.com/v1/responses"))
        let task = URLSession.shared.dataTask(with: URLRequest(url: url))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        ))

        var disposition: URLSession.ResponseDisposition?
        delegate.urlSession(URLSession.shared, dataTask: task, didReceive: response) {
            disposition = $0
        }

        var events: [StreamEvent] = []
        for await event in continuation.stream {
            events.append(event)
        }

        #expect(disposition == .cancel)

        guard events.count == 1 else {
            Issue.record("Expected exactly one emitted stream event")
            return
        }

        guard case let .error(error) = events[0] else {
            Issue.record("Expected emitted error event")
            return
        }

        guard case let .httpError(statusCode, message) = error else {
            Issue.record("Expected emitted HTTP error")
            return
        }

        #expect(statusCode == 500)
        #expect(message == "Server error (500)")
    }
}
