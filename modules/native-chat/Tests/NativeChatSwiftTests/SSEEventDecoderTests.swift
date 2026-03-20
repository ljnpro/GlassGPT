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

        for _ in 0 ..< 5 {
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

        #expect(decoder.consecutiveDecodeFailures == 5)

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
}
