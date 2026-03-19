import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

// MARK: - SSE Event Decoder Tests

extension OpenAIStreamEventTranslatorTests {
    @Test func `sse decoder tracks thinking delta and sequence`() async {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let thinkingResult = decoder.decode(
            frame: SSEFrame(
                type: "response.reasoning_text.delta",
                data: #"{"delta":"plan","sequence_number":3}"#
            ),
            continuation: continuation.continuation
        )

        if case .continued = thinkingResult {} else {
            Issue.record("Expected thinking delta to continue")
        }

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        guard emitted.count >= 3 else {
            Issue.record("Expected thinking and sequence events")
            return
        }
        if case .thinkingStarted = emitted[0] {} else {
            Issue.record("Expected thinkingStarted as first emitted event")
        }
        if case let .thinkingDelta(delta) = emitted[1] {
            #expect(delta == "plan")
        } else {
            Issue.record("Expected thinkingDelta as second emitted event")
        }
        if case let .sequenceUpdate(sequence) = emitted[2] {
            #expect(sequence == 3)
        } else {
            Issue.record("Expected sequenceUpdate as third emitted event")
        }
    }

    @Test func `sse decoder handles terminal completed payload`() throws {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let terminalData = try makeCompletedTerminalData()
        let terminalResult = decoder.decode(
            frame: SSEFrame(
                type: "response.completed",
                data: terminalData
            ),
            continuation: continuation.continuation
        )

        decoder.yieldThinkingFinishedIfNeeded(continuation: continuation.continuation)
        continuation.continuation.finish()

        if case .terminalCompleted = terminalResult {} else {
            Issue.record("Expected completed terminal result")
        }
        #expect(decoder.accumulatedThinking == "summary")
        #expect(decoder.accumulatedText == "Final output")
        #expect(decoder.sawTerminalEvent)
    }

    @Test func `sse decoder handles output done and incomplete terminal`() async throws {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let outputDoneResult = decoder.decode(
            frame: SSEFrame(
                type: "response.output_text.done",
                data: #"{"text":"materialized text","sequence_number":12}"#
            ),
            continuation: continuation.continuation
        )

        let incompleteData = try makeIncompleteTerminalData()
        let incompleteResult = decoder.decode(
            frame: SSEFrame(
                type: "response.incomplete",
                data: incompleteData
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .continued = outputDoneResult {} else {
            Issue.record("Expected output_text.done to continue")
        }
        if case let .terminalIncomplete(message) = incompleteResult {
            #expect(message == "needs recovery")
        } else {
            Issue.record("Expected incomplete terminal result")
        }
        #expect(decoder.accumulatedText == "terminal text")
        #expect(decoder.terminalThinking == nil)
        #expect(decoder.terminalFilePathAnnotations == nil)
        #expect(
            emitted.map { eventDescription($0) }
                == ["sequenceUpdate(12)"]
        )
    }

    @Test func `sse decoder emits response identifier from in progress frames`() async throws {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let inProgressData = try makeInProgressFrameData(
            responseID: "resp_in_progress",
            sequenceNumber: 9
        )
        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.in_progress",
                data: inProgressData
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .continued = result {} else {
            Issue.record("Expected in-progress frame to continue")
        }

        #expect(
            emitted.map { eventDescription($0) }
                == ["responseCreated(resp_in_progress)", "sequenceUpdate(9)"]
        )
        #expect(decoder.emittedResponseID == "resp_in_progress")
    }

    @Test func `sse decoder does not duplicate response identifier`() async throws {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let firstData = try makeInProgressFrameData(
            responseID: "resp_dedupe",
            sequenceNumber: 2
        )
        _ = decoder.decode(
            frame: SSEFrame(type: "response.in_progress", data: firstData),
            continuation: continuation.continuation
        )

        let completedData = try makeCompletedDedupeData()
        let result = decoder.decode(
            frame: SSEFrame(type: "response.completed", data: completedData),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .terminalCompleted = result {} else {
            Issue.record("Expected completed frame to be terminal")
        }

        #expect(
            emitted.map { eventDescription($0) }
                == ["responseCreated(resp_dedupe)", "sequenceUpdate(2)"]
        )
    }

    @Test func `sse frame buffer reassembles chunked frames`() {
        var buffer = SSEFrameBuffer()

        #expect(
            buffer.append("event: response.created\ndata: {\"response\":{\"id\":\"resp_123\"}}").isEmpty
        )

        let frames = buffer.append(
            "\n\nevent: response.output_text.delta\ndata: {\"delta\":\"Hi\"}\n\n"
        )

        #expect(
            frames == [
                SSEFrame(
                    type: "response.created",
                    data: #"{"response":{"id":"resp_123"}}"#
                ),
                SSEFrame(
                    type: "response.output_text.delta",
                    data: #"{"delta":"Hi"}"#
                )
            ]
        )
    }
}

// MARK: - SSE Test Data Builders

extension OpenAIStreamEventTranslatorTests {
    func makeCompletedTerminalData() throws -> String {
        try String(
            data: JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: ResponsesResponseDTO(
                        output: [
                            ResponsesOutputItemDTO(
                                type: "message",
                                id: nil,
                                content: [
                                    ResponsesContentPartDTO(
                                        type: "output_text",
                                        text: "Final output",
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
                        ],
                        reasoning: ResponsesReasoningDTO(
                            text: nil,
                            summary: [ResponsesTextFragmentDTO(text: "summary")]
                        )
                    ),
                    sequenceNumber: 4,
                    error: nil,
                    message: nil
                )
            ),
            encoding: .utf8
        ) ?? ""
    }

    func makeIncompleteTerminalData() throws -> String {
        try String(
            data: JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: ResponsesResponseDTO(
                        outputText: "terminal text",
                        message: "needs recovery"
                    ),
                    sequenceNumber: nil,
                    error: nil,
                    message: nil
                )
            ),
            encoding: .utf8
        ) ?? ""
    }

    func makeInProgressFrameData(
        responseID: String,
        sequenceNumber: Int
    ) throws -> String {
        try String(
            data: JSONCoding.encode(
                makeEnvelope(
                    response: ResponsesResponseDTO(
                        id: responseID,
                        status: "in_progress"
                    ),
                    sequenceNumber: sequenceNumber
                )
            ),
            encoding: .utf8
        ) ?? ""
    }

    func makeCompletedDedupeData() throws -> String {
        try String(
            data: JSONCoding.encode(
                makeEnvelope(
                    response: ResponsesResponseDTO(
                        id: "resp_dedupe",
                        outputText: "done"
                    ),
                    sequenceNumber: 3
                )
            ),
            encoding: .utf8
        ) ?? ""
    }
}
