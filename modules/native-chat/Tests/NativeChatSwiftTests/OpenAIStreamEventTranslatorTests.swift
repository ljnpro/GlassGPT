import Foundation
import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAIStreamEventTranslatorTests {
    @Test func translateRecognizesResponseCreatedAndTextDelta() throws {
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
            #expect(id == "resp_123")
        default:
            Issue.record("Expected response.created to translate to .responseCreated")
        }

        switch delta {
        case .textDelta(let text):
            #expect(text == "Hi")
        default:
            Issue.record("Expected response.output_text.delta to translate to .textDelta")
        }
    }

    @Test func translateRecognizesFailureEvents() throws {
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

        switch errorEvent {
        case .error(let error):
            #expect(error.errorDescription == "backend failed")
        default:
            Issue.record("Expected response.failed to translate to .error")
        }
    }

    @Test func translateRecognizesAnnotationEvents() throws {
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

        switch annotationEvent {
        case .annotationAdded(let citation):
            #expect(citation.url == "https://example.com")
            #expect(citation.title == "Example")
        default:
            Issue.record("Expected annotation event to translate to .annotationAdded")
        }
    }

    @Test func translateIgnoresIncompletePayloadsAndPassiveEvents() throws {
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.created",
                data: try JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.output_text.delta",
                data: try JSONCoding.encode(makeEnvelope(delta: ""))
            ) == nil
        )
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.web_search_call.completed",
                data: try JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.queued",
                data: try JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "unknown.event",
                data: try JSONCoding.encode(makeEnvelope())
            ) == nil
        )
        #expect(
            OpenAIStreamEventTranslator.translate(
                eventType: "response.created",
                data: Data("not-json".utf8)
            ) == nil
        )
    }

    @Test func extractSequenceNumberUsesEnvelopeAndResolvedResponse() throws {
        #expect(
            OpenAIStreamEventTranslator.extractSequenceNumber(
                from: try JSONCoding.encode(makeEnvelope(sequenceNumber: 12))
            ) == 12
        )

        #expect(
            OpenAIStreamEventTranslator.extractSequenceNumber(
                from: try JSONCoding.encode(
                    makeEnvelope(
                        response: ResponsesResponseDTO(sequenceNumber: 27)
                    )
                )
            ) == 27
        )

        #expect(OpenAIStreamEventTranslator.extractSequenceNumber(from: Data("oops".utf8)) == nil)
    }

    @Test func extractResponseIdentifierUsesEnvelopeAndResolvedResponse() throws {
        #expect(
            OpenAIStreamEventTranslator.extractResponseIdentifier(
                from: try JSONCoding.encode(
                    makeEnvelope(response: ResponsesResponseDTO(id: "resp_envelope"))
                )
            ) == "resp_envelope"
        )

        #expect(
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
            ) == nil
        )

        #expect(OpenAIStreamEventTranslator.extractResponseIdentifier(from: Data("oops".utf8)) == nil)
    }

    @Test func extractFilePathAnnotationsUsesAnnotatedSubstring() {
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
        case .responseCreated(let id):
            return "responseCreated(\(id))"
        case .sequenceUpdate(let sequence):
            return "sequenceUpdate(\(sequence))"
        default:
            return String(describing: event)
        }
    }
}
