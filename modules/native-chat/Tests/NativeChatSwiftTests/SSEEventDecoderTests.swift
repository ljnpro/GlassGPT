import Foundation
import Testing
@testable import OpenAITransport

struct SSEEventDecoderTests {
    @Test func `decoder tracks consecutive malformed frames and resets after success`() {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        for _ in 0 ..< 4 {
            let result = decoder.decode(
                frame: SSEFrame(
                    type: "response.output_text.delta",
                    data: "{"
                ),
                continuation: continuation.continuation
            )

            if case .continued = result {} else {
                Issue.record("Malformed frames should not terminate the stream")
            }
        }

        #expect(decoder.consecutiveDecodeFailures == 4)

        _ = decoder.decode(
            frame: SSEFrame(
                type: "response.output_text.delta",
                data: #"{"delta":"ok"}"#
            ),
            continuation: continuation.continuation
        )

        #expect(decoder.consecutiveDecodeFailures == 0)
        continuation.continuation.finish()
    }

    @Test(arguments: [
        (4, false),
        (5, true),
        (6, false)
    ])
    func `decoder logs only when malformed frame threshold is first reached`(
        count: Int,
        shouldLog: Bool
    ) {
        let decoder = SSEEventDecoder()

        #expect(decoder.shouldLogDecodeFailure(after: count) == shouldLog)
    }

    @Test func `decoder emits response identifier from created frame with string reasoning summary mode`() async {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.created",
                data: #"""
                {
                  "response": {
                    "id": "resp_modern",
                    "status": "in_progress",
                    "reasoning": {
                      "effort": "xhigh",
                      "summary": "detailed"
                    }
                  },
                  "sequence_number": 0
                }
                """#
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var events: [StreamEvent] = []
        for await event in continuation.stream {
            events.append(event)
        }

        if case .continued = result {} else {
            Issue.record("Created frame should continue streaming")
        }

        #expect(events.count == 2)
        guard events.count == 2 else { return }
        guard case let .responseCreated(responseID) = events[0] else {
            Issue.record("Expected responseCreated event")
            return
        }
        #expect(responseID == "resp_modern")
        guard case let .sequenceUpdate(sequenceNumber) = events[1] else {
            Issue.record("Expected sequenceUpdate event")
            return
        }
        #expect(sequenceNumber == 0)
    }

    @Test func `decoder replaces visible text when streaming switches to a new output item`() async {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        _ = decoder.decode(
            frame: SSEFrame(
                type: "response.output_text.delta",
                data: #"{"item_id":"msg_first","delta":"Hi"}"#
            ),
            continuation: continuation.continuation
        )
        _ = decoder.decode(
            frame: SSEFrame(
                type: "response.output_text.delta",
                data: #"{"item_id":"msg_second","delta":"Hello"}"#
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var events: [StreamEvent] = []
        for await event in continuation.stream {
            events.append(event)
        }

        #expect(events.count == 2)
        guard events.count == 2 else { return }
        guard case let .textDelta(firstDelta) = events[0] else {
            Issue.record("Expected first event to append initial text")
            return
        }
        #expect(firstDelta == "Hi")
        guard case let .replaceText(replacement) = events[1] else {
            Issue.record("Expected second event to replace text for new item")
            return
        }
        #expect(replacement == "Hello")
        #expect(decoder.accumulatedText == "Hello")
        #expect(decoder.activeTextItemID == "msg_second")
    }
}
