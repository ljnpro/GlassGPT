import Foundation
import Testing
@testable import OpenAITransport

extension SSEEventDecoderTests {
    @Test func `decoder completes modern terminal frame with string reasoning summary mode`() {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.completed",
                data: #"""
                {
                  "response": {
                    "id": "resp_modern",
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
                  },
                  "sequence_number": 96
                }
                """#
            ),
            continuation: continuation.continuation
        )

        if case .terminalCompleted = result {} else {
            Issue.record("Completed frame should be terminal")
        }
        #expect(decoder.accumulatedText == "Hi! How can I help?")
        #expect(decoder.sawTerminalEvent)
        continuation.continuation.finish()
    }

    @Test func `decoder completes terminal frame with nested string reasoning summary`() {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.completed",
                data: #"""
                {
                  "response": {
                    "id": "resp_nested",
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
                  },
                  "sequence_number": 24
                }
                """#
            ),
            continuation: continuation.continuation
        )

        if case .terminalCompleted = result {} else {
            Issue.record("Completed frame should be terminal")
        }
        #expect(decoder.accumulatedText == "Hi! How can I help?")
        #expect(decoder.sawTerminalEvent)
        continuation.continuation.finish()
    }

    @Test func `decoder completes live xhigh greeting payload with reasoning summary and final answer`() {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.completed",
                data: #"""
                {
                  "response": {
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
                  },
                  "sequence_number": 101
                }
                """#
            ),
            continuation: continuation.continuation
        )

        if case .terminalCompleted = result {} else {
            Issue.record("Completed frame should be terminal")
        }
        #expect(decoder.emittedResponseID == "resp_xhigh_hi")
        #expect(decoder.accumulatedText == "Hi! How can I help?")
        #expect(decoder.accumulatedThinking == "**Preparing friendly response**")
        #expect(decoder.sawTerminalEvent)
        continuation.continuation.finish()
    }
}
