import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAIStreamEventTranslatorTests {
    @Test func `translate recognizes response created and text delta`() throws {
        let created = try OpenAIStreamEventTranslator.translate(
            eventType: "response.created",
            data: JSONCoding.encode(
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
        let delta = try OpenAIStreamEventTranslator.translate(
            eventType: "response.output_text.delta",
            data: JSONCoding.encode(
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
        case let .responseCreated(id):
            #expect(id == "resp_123")
        default:
            Issue.record("Expected response.created to translate to .responseCreated")
        }

        switch delta {
        case let .textDelta(text):
            #expect(text == "Hi")
        default:
            Issue.record("Expected response.output_text.delta to translate to .textDelta")
        }
    }

    @Test func `translate recognizes failure events`() throws {
        let errorEvent = try OpenAIStreamEventTranslator.translate(
            eventType: "response.failed",
            data: JSONCoding.encode(
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

        switch errorEvent {
        case let .error(error):
            #expect(error.errorDescription == "backend failed")
        default:
            Issue.record("Expected response.failed to translate to .error")
        }
    }

    @Test func `translate recognizes annotation events`() throws {
        let annotationEvent = try OpenAIStreamEventTranslator.translate(
            eventType: "response.output_text.annotation.added",
            data: JSONCoding.encode(
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

        switch annotationEvent {
        case let .annotationAdded(citation):
            #expect(citation.url == "https://example.com")
            #expect(citation.title == "Example")
        default:
            Issue.record("Expected annotation event to translate to .annotationAdded")
        }
    }

    @Test func `translate ignores incomplete payloads and passive events`() throws {
        #expect(
            try OpenAIStreamEventTranslator.translate(
                eventType: "response.created",
                data: JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            try OpenAIStreamEventTranslator.translate(
                eventType: "response.output_text.delta",
                data: JSONCoding.encode(makeEnvelope(delta: ""))
            ) == nil
        )
        #expect(
            try OpenAIStreamEventTranslator.translate(
                eventType: "response.web_search_call.completed",
                data: JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            try OpenAIStreamEventTranslator.translate(
                eventType: "response.queued",
                data: JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            try OpenAIStreamEventTranslator.translate(
                eventType: "unknown.event",
                data: JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.created",
                data: Data("not-json".utf8)
            ) == nil
        )
    }

    @Test func `extract sequence number uses envelope and resolved response`() throws {
        #expect(
            try OpenAIStreamEventTranslator.extractSequenceNumber(
                from: JSONCoding.encode(makeEnvelope(sequenceNumber: 12))
            ) == 12
        )

        #expect(
            try OpenAIStreamEventTranslator.extractSequenceNumber(
                from: JSONCoding.encode(
                    makeEnvelope(
                        response: ResponsesResponseDTO(sequenceNumber: 27)
                    )
                )
            ) == 27
        )

        #expect(OpenAIStreamEventTranslator.extractSequenceNumber(from: Data("oops".utf8)) == nil)
    }

    @Test func `extract response identifier uses envelope and resolved response`() throws {
        #expect(
            try OpenAIStreamEventTranslator.extractResponseIdentifier(
                from: JSONCoding.encode(
                    makeEnvelope(response: ResponsesResponseDTO(id: "resp_envelope"))
                )
            ) == "resp_envelope"
        )

        #expect(
            try OpenAIStreamEventTranslator.extractResponseIdentifier(
                from: JSONCoding.encode(
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
            ) == nil
        )

        #expect(OpenAIStreamEventTranslator.extractResponseIdentifier(from: Data("oops".utf8)) == nil)
    }

    @Test func `extract file path annotations uses annotated substring`() {
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

        #expect(annotations == [
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
}

// MARK: - Helpers

extension OpenAIStreamEventTranslatorTests {
    func assertTranslation(
        eventType: String,
        envelope: ResponsesStreamEnvelopeDTO,
        assertion: (StreamEvent) -> Void
    ) {
        do {
            let data = try JSONCoding.encode(envelope)
            guard let event = OpenAIStreamEventTranslator.translate(
                eventType: eventType,
                data: data
            ) else {
                Issue.record("Translation returned nil for \(eventType)")
                return
            }
            assertion(event)
        } catch {
            Issue.record("Unexpected translation failure: \(error)")
        }
    }

    func makeEnvelope(
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

    func eventDescription(_ event: StreamEvent) -> String {
        switch event {
        case let .responseCreated(id):
            "responseCreated(\(id))"
        case let .sequenceUpdate(sequence):
            "sequenceUpdate(\(sequence))"
        case let .replaceText(text):
            "replaceText(\(text))"
        default:
            String(describing: event)
        }
    }
}
