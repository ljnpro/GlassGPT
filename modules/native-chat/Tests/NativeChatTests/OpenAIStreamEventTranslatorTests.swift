import XCTest
@testable import NativeChat

final class OpenAIStreamEventTranslatorTests: XCTestCase {
    func testTranslateRecognizesResponseCreatedAndTextDelta() throws {
        let created = OpenAIStreamEventTranslator.translate(
            eventType: "response.created",
            data: try JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: ResponsesResponseDTO(id: "resp_123"),
                    sequenceNumber: nil,
                    error: nil,
                    message: nil
                )
            )
        )
        let delta = OpenAIStreamEventTranslator.translate(
            eventType: "response.output_text.delta",
            data: try JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: "Hi",
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: nil,
                    sequenceNumber: nil,
                    error: nil,
                    message: nil
                )
            )
        )

        switch created {
        case .responseCreated(let id):
            XCTAssertEqual(id, "resp_123")
        default:
            XCTFail("Expected response.created to translate to .responseCreated")
        }

        switch delta {
        case .textDelta(let text):
            XCTAssertEqual(text, "Hi")
        default:
            XCTFail("Expected response.output_text.delta to translate to .textDelta")
        }
    }

    func testTranslateRecognizesFailureAndAnnotationEvents() throws {
        let errorEvent = OpenAIStreamEventTranslator.translate(
            eventType: "response.failed",
            data: try JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: nil,
                    response: ResponsesResponseDTO(
                        error: ResponsesErrorDTO(message: "backend failed")
                    ),
                    sequenceNumber: nil,
                    error: nil,
                    message: nil
                )
            )
        )
        let annotationEvent = OpenAIStreamEventTranslator.translate(
            eventType: "response.output_text.annotation.added",
            data: try JSONCoding.encode(
                ResponsesStreamEnvelopeDTO(
                    delta: nil,
                    itemID: nil,
                    code: nil,
                    text: nil,
                    annotation: ResponsesAnnotationDTO(
                        type: "url_citation",
                        url: "https://example.com",
                        title: "Example",
                        startIndex: 0,
                        endIndex: 7,
                        fileID: nil,
                        containerID: nil,
                        filename: nil
                    ),
                    response: nil,
                    sequenceNumber: 9,
                    error: nil,
                    message: nil
                )
            )
        )

        switch errorEvent {
        case .error(let error):
            XCTAssertEqual(error.errorDescription, "backend failed")
        default:
            XCTFail("Expected response.failed to translate to .error")
        }

        switch annotationEvent {
        case .annotationAdded(let citation):
            XCTAssertEqual(citation.url, "https://example.com")
            XCTAssertEqual(citation.title, "Example")
        default:
            XCTFail("Expected annotation event to translate to .annotationAdded")
        }
    }

    func testTranslateRecognizesToolLifecycleEvents() throws {
        assertTranslation(
            eventType: "response.web_search_call.in_progress",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case .webSearchStarted(let itemID) = event else {
                return XCTFail("Expected web search started event")
            }
            XCTAssertEqual(itemID, "ws_1")
        }

        assertTranslation(
            eventType: "response.web_search_call.searching",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case .webSearchSearching(let itemID) = event else {
                return XCTFail("Expected web search searching event")
            }
            XCTAssertEqual(itemID, "ws_1")
        }

        assertTranslation(
            eventType: "response.web_search_call.completed",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case .webSearchCompleted(let itemID) = event else {
                return XCTFail("Expected web search completed event")
            }
            XCTAssertEqual(itemID, "ws_1")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call.in_progress",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterStarted(let itemID) = event else {
                return XCTFail("Expected code interpreter started event")
            }
            XCTAssertEqual(itemID, "ci_1")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call.interpreting",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterInterpreting(let itemID) = event else {
                return XCTFail("Expected code interpreter interpreting event")
            }
            XCTAssertEqual(itemID, "ci_1")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call_code.delta",
            envelope: makeEnvelope(delta: "print", itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterCodeDelta(let itemID, let delta) = event else {
                return XCTFail("Expected code interpreter code delta event")
            }
            XCTAssertEqual(itemID, "ci_1")
            XCTAssertEqual(delta, "print")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call_code.done",
            envelope: makeEnvelope(itemID: "ci_1", code: "print(1)")
        ) { event in
            guard case .codeInterpreterCodeDone(let itemID, let code) = event else {
                return XCTFail("Expected code interpreter code done event")
            }
            XCTAssertEqual(itemID, "ci_1")
            XCTAssertEqual(code, "print(1)")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call.completed",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterCompleted(let itemID) = event else {
                return XCTFail("Expected code interpreter completed event")
            }
            XCTAssertEqual(itemID, "ci_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.in_progress",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case .fileSearchStarted(let itemID) = event else {
                return XCTFail("Expected file search started event")
            }
            XCTAssertEqual(itemID, "fs_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.searching",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case .fileSearchSearching(let itemID) = event else {
                return XCTFail("Expected file search searching event")
            }
            XCTAssertEqual(itemID, "fs_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.completed",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case .fileSearchCompleted(let itemID) = event else {
                return XCTFail("Expected file search completed event")
            }
            XCTAssertEqual(itemID, "fs_1")
        }
    }

    func testTranslateHandlesTerminalAndErrorEvents() throws {
        let fileAnnotation = ResponsesAnnotationDTO(
            type: "file_path",
            url: nil,
            title: nil,
            startIndex: 0,
            endIndex: 13,
            fileID: "file_terminal",
            containerID: "container_1",
            filename: "report.txt"
        )
        let terminalResponse = ResponsesResponseDTO(
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    id: nil,
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "sandbox:/tmp/report.txt",
                            annotations: [fileAnnotation]
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
                text: "plan",
                summary: [ResponsesTextFragmentDTO(text: " summary")]
            ),
            message: "needs recovery"
        )

        assertTranslation(
            eventType: "response.completed",
            envelope: makeEnvelope(response: terminalResponse)
        ) { event in
            guard case .completed(let text, let thinking, let annotations) = event else {
                return XCTFail("Expected completed event")
            }
            XCTAssertEqual(text, "sandbox:/tmp/report.txt")
            XCTAssertEqual(thinking, "plan summary")
            XCTAssertEqual(annotations?.first?.fileId, "file_terminal")
        }

        assertTranslation(
            eventType: "response.incomplete",
            envelope: makeEnvelope(response: terminalResponse)
        ) { event in
            guard case .incomplete(let text, let thinking, let annotations, let message) = event else {
                return XCTFail("Expected incomplete event")
            }
            XCTAssertEqual(text, "sandbox:/tmp/report.txt")
            XCTAssertEqual(thinking, "plan summary")
            XCTAssertEqual(annotations?.first?.filename, "report.txt")
            XCTAssertEqual(message, "needs recovery")
        }

        assertTranslation(
            eventType: "error",
            envelope: makeEnvelope(message: "stream exploded")
        ) { event in
            guard case .error(let error) = event else {
                return XCTFail("Expected error event")
            }
            XCTAssertEqual(error.errorDescription, "stream exploded")
        }

        assertTranslation(
            eventType: "response.failed",
            envelope: makeEnvelope()
        ) { event in
            guard case .error(let error) = event else {
                return XCTFail("Expected failed event to map to error")
            }
            XCTAssertEqual(error.errorDescription, "Response generation failed.")
        }
    }

    func testTranslateIgnoresIncompletePayloadsAndPassiveEvents() throws {
        XCTAssertNil(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.created",
                data: try JSONCoding.encode(makeEnvelope())
            )
        )
        XCTAssertNil(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.output_text.delta",
                data: try JSONCoding.encode(makeEnvelope(delta: ""))
            )
        )
        XCTAssertNil(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.web_search_call.completed",
                data: try JSONCoding.encode(makeEnvelope())
            )
        )
        XCTAssertNil(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.queued",
                data: try JSONCoding.encode(makeEnvelope())
            )
        )
        XCTAssertNil(
            OpenAIStreamEventTranslator.translate(
                eventType: "unknown.event",
                data: try JSONCoding.encode(makeEnvelope())
            )
        )
        XCTAssertNil(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.created",
                data: Data("not-json".utf8)
            )
        )
    }

    func testExtractSequenceNumberUsesEnvelopeAndResolvedResponse() throws {
        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractSequenceNumber(
                from: try JSONCoding.encode(makeEnvelope(sequenceNumber: 12))
            ),
            12
        )

        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractSequenceNumber(
                from: try JSONCoding.encode(
                    makeEnvelope(
                        response: ResponsesResponseDTO(sequenceNumber: 27)
                    )
                )
            ),
            27
        )

        XCTAssertNil(OpenAIStreamEventTranslator.extractSequenceNumber(from: Data("oops".utf8)))
    }

    func testExtractResponseIdentifierUsesEnvelopeAndResolvedResponse() throws {
        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractResponseIdentifier(
                from: try JSONCoding.encode(
                    makeEnvelope(response: ResponsesResponseDTO(id: "resp_envelope"))
                )
            ),
            "resp_envelope"
        )

        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractResponseIdentifier(
                from: try JSONCoding.encode(
                    ResponsesStreamEnvelopeDTO(
                        delta: nil,
                        itemID: nil,
                        code: nil,
                        text: nil,
                        annotation: nil,
                        response: nil,
                        sequenceNumber: nil,
                        error: nil,
                        message: nil
                    )
                )
            ),
            nil
        )

        XCTAssertNil(OpenAIStreamEventTranslator.extractResponseIdentifier(from: Data("oops".utf8)))
    }

    func testExtractFilePathAnnotationsUsesAnnotatedSubstring() {
        let text = "sandbox:/mnt/data/report.pdf"
        let annotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(
            from: ResponsesResponseDTO(
                output: [
                    ResponsesOutputItemDTO(
                        type: "message",
                        id: nil,
                        content: [
                            ResponsesContentPartDTO(
                                type: "output_text",
                                text: text,
                                annotations: [
                                    ResponsesAnnotationDTO(
                                        type: "file_path",
                                        url: nil,
                                        title: nil,
                                        startIndex: 0,
                                        endIndex: text.count,
                                        fileID: "file_report",
                                        containerID: "container_123",
                                        filename: "report.pdf"
                                    )
                                ]
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

        XCTAssertEqual(annotations, [
            FilePathAnnotation(
                fileId: "file_report",
                containerId: "container_123",
                sandboxPath: text,
                filename: "report.pdf",
                startIndex: 0,
                endIndex: text.count
            )
        ])
    }

    func testExtractionHelpersPreferStructuredContentAndGracefullyHandleEdgeCases() {
        let response = ResponsesResponseDTO(
            outputText: "top level text",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    id: nil,
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "body",
                            annotations: [
                                ResponsesAnnotationDTO(
                                    type: "file_path",
                                    url: nil,
                                    title: nil,
                                    startIndex: 0,
                                    endIndex: 999,
                                    fileID: "file_1",
                                    containerID: nil,
                                    filename: "body.txt"
                                ),
                                ResponsesAnnotationDTO(
                                    type: "file_path",
                                    url: nil,
                                    title: nil,
                                    startIndex: 0,
                                    endIndex: 3,
                                    fileID: nil,
                                    containerID: nil,
                                    filename: nil
                                )
                            ]
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
                ),
                ResponsesOutputItemDTO(
                    type: "reasoning",
                    id: nil,
                    content: [ResponsesContentPartDTO(type: "output_text", text: " step", annotations: nil)],
                    action: nil,
                    query: nil,
                    queries: nil,
                    code: nil,
                    results: nil,
                    outputs: nil,
                    text: "plan",
                    summary: [ResponsesTextFragmentDTO(text: " summary") ]
                )
            ],
            reasoning: ResponsesReasoningDTO(
                text: "top",
                summary: [ResponsesTextFragmentDTO(text: " level")]
            ),
            error: ResponsesErrorDTO(message: "structured")
        )

        XCTAssertEqual(OpenAIStreamEventTranslator.extractOutputText(from: response), "top level text")
        XCTAssertEqual(OpenAIStreamEventTranslator.extractReasoningText(from: response), "top levelplan summary step")
        XCTAssertEqual(OpenAIStreamEventTranslator.extractErrorMessage(from: response), "structured")

        let annotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: response)
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.sandboxPath, "body")
    }

    func testAnnotationHelpersValidatePayloadsAndSubstringBounds() {
        let urlAnnotation = ResponsesAnnotationDTO(
            type: "url_citation",
            url: "https://example.com",
            title: "Example",
            startIndex: 1,
            endIndex: 4,
            fileID: nil,
            containerID: nil,
            filename: nil
        )
        let fileAnnotation = ResponsesAnnotationDTO(
            type: "container_file_citation",
            url: nil,
            title: nil,
            startIndex: 0,
            endIndex: 5,
            fileID: "file_1",
            containerID: "container_1",
            filename: "note.txt"
        )

        guard case .annotationAdded(let citation) = OpenAIStreamEventTranslator.annotationEvent(from: urlAnnotation) else {
            return XCTFail("Expected URL citation event")
        }
        XCTAssertEqual(citation.startIndex, 1)
        XCTAssertEqual(citation.endIndex, 4)

        guard case .filePathAnnotationAdded(let pathAnnotation) = OpenAIStreamEventTranslator.annotationEvent(from: fileAnnotation) else {
            return XCTFail("Expected file path annotation event")
        }
        XCTAssertEqual(pathAnnotation.fileId, "file_1")
        XCTAssertEqual(pathAnnotation.filename, "note.txt")

        XCTAssertNil(
            OpenAIStreamEventTranslator.annotationEvent(
                from: ResponsesAnnotationDTO(
                    type: "url_citation",
                    url: nil,
                    title: "Missing URL",
                    startIndex: nil,
                    endIndex: nil,
                    fileID: nil,
                    containerID: nil,
                    filename: nil
                )
            )
        )
        XCTAssertNil(
            OpenAIStreamEventTranslator.annotationEvent(
                from: ResponsesAnnotationDTO(
                    type: "file_path",
                    url: nil,
                    title: nil,
                    startIndex: nil,
                    endIndex: nil,
                    fileID: nil,
                    containerID: nil,
                    filename: nil
                )
            )
        )

        XCTAssertTrue(OpenAIStreamEventTranslator.isFileCitationAnnotationType("file_path"))
        XCTAssertTrue(OpenAIStreamEventTranslator.isFileCitationAnnotationType("container_file_citation"))
        XCTAssertFalse(OpenAIStreamEventTranslator.isFileCitationAnnotationType("url_citation"))

        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef",
                startIndex: 1,
                endIndex: 4
            ),
            "bcd"
        )
        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef",
                startIndex: 3,
                endIndex: 20
            ),
            "def"
        )
        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef",
                startIndex: -1,
                endIndex: 2
            ),
            ""
        )
        XCTAssertEqual(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef",
                startIndex: 5,
                endIndex: 5
            ),
            ""
        )
    }

    func testSSEEventDecoderTracksThinkingAndTerminalPayload() async throws {
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
        let terminalResult = decoder.decode(
            frame: SSEFrame(
                type: "response.completed",
                data: try String(
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
            ),
            continuation: continuation.continuation
        )

        decoder.yieldThinkingFinishedIfNeeded(continuation: continuation.continuation)
        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .continued = thinkingResult {} else {
            XCTFail("Expected thinking delta to continue")
        }
        if case .terminalCompleted = terminalResult {} else {
            XCTFail("Expected completed terminal result")
        }
        XCTAssertEqual(decoder.accumulatedThinking, "summary")
        XCTAssertEqual(decoder.accumulatedText, "Final output")
        XCTAssertTrue(decoder.sawTerminalEvent)

        guard emitted.count >= 3 else {
            return XCTFail("Expected thinking and sequence events")
        }
        if case .thinkingStarted = emitted[0] {} else {
            XCTFail("Expected thinkingStarted as first emitted event")
        }
        if case .thinkingDelta(let delta) = emitted[1] {
            XCTAssertEqual(delta, "plan")
        } else {
            XCTFail("Expected thinkingDelta as second emitted event")
        }
        if case .sequenceUpdate(let sequence) = emitted[2] {
            XCTAssertEqual(sequence, 3)
        } else {
            XCTFail("Expected sequenceUpdate as third emitted event")
        }
    }

    func testSSEEventDecoderHandlesOutputDoneAndIncompleteTerminalMessage() async throws {
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
        let incompleteResult = decoder.decode(
            frame: SSEFrame(
                type: "response.incomplete",
                data: try String(
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
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .continued = outputDoneResult {} else {
            XCTFail("Expected output_text.done to continue")
        }
        if case .terminalIncomplete(let message) = incompleteResult {
            XCTAssertEqual(message, "needs recovery")
        } else {
            XCTFail("Expected incomplete terminal result")
        }
        XCTAssertEqual(decoder.accumulatedText, "terminal text")
        XCTAssertEqual(decoder.terminalThinking, nil)
        XCTAssertNil(decoder.terminalFilePathAnnotations)
        XCTAssertEqual(
            emitted.map { eventDescription($0) },
            ["sequenceUpdate(12)"]
        )
    }

    func testSSEEventDecoderEmitsResponseIdentifierFromInProgressFrames() async throws {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.in_progress",
                data: try String(
                    data: JSONCoding.encode(
                        makeEnvelope(
                            response: ResponsesResponseDTO(
                                id: "resp_in_progress",
                                status: "in_progress"
                            ),
                            sequenceNumber: 9
                        )
                    ),
                    encoding: .utf8
                ) ?? ""
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .continued = result {} else {
            XCTFail("Expected in-progress frame to continue")
        }

        XCTAssertEqual(
            emitted.map { eventDescription($0) },
            ["responseCreated(resp_in_progress)", "sequenceUpdate(9)"]
        )
        XCTAssertEqual(decoder.emittedResponseID, "resp_in_progress")
    }

    func testSSEEventDecoderDoesNotDuplicateResponseIdentifierAfterInitialEmission() async throws {
        var decoder = SSEEventDecoder()
        let continuation = makeTestAsyncStream() as (
            stream: AsyncStream<StreamEvent>,
            continuation: AsyncStream<StreamEvent>.Continuation
        )

        _ = decoder.decode(
            frame: SSEFrame(
                type: "response.in_progress",
                data: try String(
                    data: JSONCoding.encode(
                        makeEnvelope(
                            response: ResponsesResponseDTO(id: "resp_dedupe", status: "in_progress"),
                            sequenceNumber: 2
                        )
                    ),
                    encoding: .utf8
                ) ?? ""
            ),
            continuation: continuation.continuation
        )
        let result = decoder.decode(
            frame: SSEFrame(
                type: "response.completed",
                data: try String(
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
            ),
            continuation: continuation.continuation
        )

        continuation.continuation.finish()

        var emitted: [StreamEvent] = []
        for await event in continuation.stream {
            emitted.append(event)
        }

        if case .terminalCompleted = result {} else {
            XCTFail("Expected completed frame to be terminal")
        }

        XCTAssertEqual(
            emitted.map { eventDescription($0) },
            ["responseCreated(resp_dedupe)", "sequenceUpdate(2)"]
        )
    }

    func testSSEFrameBufferReassemblesChunkedFrames() {
        var buffer = SSEFrameBuffer()

        XCTAssertTrue(
            buffer.append("event: response.created\ndata: {\"response\":{\"id\":\"resp_123\"}}").isEmpty
        )

        let frames = buffer.append("\n\nevent: response.output_text.delta\ndata: {\"delta\":\"Hi\"}\n\n")

        XCTAssertEqual(
            frames,
            [
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

    private func assertTranslation(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO,
        assertion: (StreamEvent) -> Void
    ) {
        do {
            let event = try XCTUnwrap(
                OpenAIStreamEventTranslator.translate(
                    eventType: eventType,
                    data: JSONCoding.encode(envelope)
                )
            )
            assertion(event)
        } catch {
            XCTFail("Unexpected translation failure: \(error)")
        }
    }

    private func makeEnvelope(
        delta: String? = nil,
        itemID: String? = nil,
        code: String? = nil,
        response: ResponsesResponseDTO? = nil,
        sequenceNumber: Int? = nil,
        message: String? = nil
    ) -> ResponsesStreamEnvelopeDTO {
        ResponsesStreamEnvelopeDTO(
            delta: delta,
            itemID: itemID,
            code: code,
            text: nil,
            annotation: nil,
            response: response,
            sequenceNumber: sequenceNumber,
            error: message.map { ResponsesErrorDTO(message: $0) },
            message: message
        )
    }

    private func eventDescription(_ event: StreamEvent) -> String {
        switch event {
        case .responseCreated(let id):
            return "responseCreated(\(id))"
        case .sequenceUpdate(let sequence):
            return "sequenceUpdate(\(sequence))"
        default:
            return String(describing: event)
        }
    }
}
