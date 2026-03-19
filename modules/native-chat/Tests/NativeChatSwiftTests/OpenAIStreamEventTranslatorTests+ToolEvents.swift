import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

extension OpenAIStreamEventTranslatorTests {
    @Test func `translate recognizes web search lifecycle events`() {
        assertTranslation(
            eventType: "response.web_search_call.in_progress",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case let .webSearchStarted(itemID) = event else {
                Issue.record("Expected web search started event")
                return
            }
            #expect(itemID == "ws_1")
        }

        assertTranslation(
            eventType: "response.web_search_call.searching",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case let .webSearchSearching(itemID) = event else {
                Issue.record("Expected web search searching event")
                return
            }
            #expect(itemID == "ws_1")
        }

        assertTranslation(
            eventType: "response.web_search_call.completed",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case let .webSearchCompleted(itemID) = event else {
                Issue.record("Expected web search completed event")
                return
            }
            #expect(itemID == "ws_1")
        }
    }

    @Test func `translate recognizes code interpreter start and interpret events`() {
        assertTranslation(
            eventType: "response.code_interpreter_call.in_progress",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case let .codeInterpreterStarted(itemID) = event else {
                Issue.record("Expected code interpreter started event")
                return
            }
            #expect(itemID == "ci_1")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call.interpreting",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case let .codeInterpreterInterpreting(itemID) = event else {
                Issue.record("Expected code interpreter interpreting event")
                return
            }
            #expect(itemID == "ci_1")
        }
    }

    @Test func `translate recognizes code interpreter code and completion events`() {
        assertTranslation(
            eventType: "response.code_interpreter_call_code.delta",
            envelope: makeEnvelope(delta: "print", itemID: "ci_1")
        ) { event in
            guard case let .codeInterpreterCodeDelta(itemID, delta) = event else {
                Issue.record("Expected code interpreter code delta event")
                return
            }
            #expect(itemID == "ci_1")
            #expect(delta == "print")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call_code.done",
            envelope: makeEnvelope(itemID: "ci_1", code: "print(1)")
        ) { event in
            guard case let .codeInterpreterCodeDone(itemID, code) = event else {
                Issue.record("Expected code interpreter code done event")
                return
            }
            #expect(itemID == "ci_1")
            #expect(code == "print(1)")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call.completed",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case let .codeInterpreterCompleted(itemID) = event else {
                Issue.record("Expected code interpreter completed event")
                return
            }
            #expect(itemID == "ci_1")
        }
    }

    @Test func `translate recognizes file search lifecycle events`() {
        assertTranslation(
            eventType: "response.file_search_call.in_progress",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case let .fileSearchStarted(itemID) = event else {
                Issue.record("Expected file search started event")
                return
            }
            #expect(itemID == "fs_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.searching",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case let .fileSearchSearching(itemID) = event else {
                Issue.record("Expected file search searching event")
                return
            }
            #expect(itemID == "fs_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.completed",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case let .fileSearchCompleted(itemID) = event else {
                Issue.record("Expected file search completed event")
                return
            }
            #expect(itemID == "fs_1")
        }
    }

    @Test func `translate handles completed terminal event`() {
        let terminalResponse = makeTerminalResponse()

        assertTranslation(
            eventType: "response.completed",
            envelope: makeEnvelope(response: terminalResponse)
        ) { event in
            guard case let .completed(text, thinking, annotations) = event else {
                Issue.record("Expected completed event")
                return
            }
            #expect(text == "sandbox:/tmp/report.txt")
            #expect(thinking == "plan summary")
            #expect(annotations?.first?.fileId == "file_terminal")
        }
    }

    @Test func `translate handles incomplete terminal event`() {
        let terminalResponse = makeTerminalResponse()

        assertTranslation(
            eventType: "response.incomplete",
            envelope: makeEnvelope(response: terminalResponse)
        ) { event in
            guard case let .incomplete(text, thinking, annotations, message) = event else {
                Issue.record("Expected incomplete event")
                return
            }
            #expect(text == "sandbox:/tmp/report.txt")
            #expect(thinking == "plan summary")
            #expect(annotations?.first?.filename == "report.txt")
            #expect(message == "needs recovery")
        }
    }

    @Test func `translate handles stream and response error events`() {
        assertTranslation(
            eventType: "error",
            envelope: makeEnvelope(message: "stream exploded")
        ) { event in
            guard case let .error(error) = event else {
                Issue.record("Expected error event")
                return
            }
            #expect(error.errorDescription == "stream exploded")
        }

        assertTranslation(
            eventType: "response.failed",
            envelope: makeEnvelope()
        ) { event in
            guard case let .error(error) = event else {
                Issue.record("Expected failed event to map to error")
                return
            }
            #expect(error.errorDescription == "Response generation failed.")
        }
    }

    @Test func `extraction helpers prefer structured content`() {
        let response = makeStructuredExtractionResponse()

        #expect(OpenAIStreamEventTranslator.extractOutputText(from: response) == "top level text")
        #expect(
            OpenAIStreamEventTranslator.extractReasoningText(from: response)
                == "top levelplan summary step"
        )
        #expect(OpenAIStreamEventTranslator.extractErrorMessage(from: response) == "structured")
    }

    @Test func `extraction helpers gracefully handle edge cases`() {
        let response = makeStructuredExtractionResponse()

        let annotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: response)
        #expect(annotations.count == 1)
        #expect(annotations.first?.sandboxPath == "body")
    }

    @Test func `annotation helpers validate URL payloads`() {
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

        guard case let .annotationAdded(citation) = OpenAIStreamEventTranslator.annotationEvent(
            from: urlAnnotation
        ) else {
            Issue.record("Expected URL citation event")
            return
        }
        #expect(citation.startIndex == 1)
        #expect(citation.endIndex == 4)
    }

    @Test func `annotation helpers validate file payloads`() {
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

        guard case let .filePathAnnotationAdded(pathAnnotation) = OpenAIStreamEventTranslator.annotationEvent(
            from: fileAnnotation
        ) else {
            Issue.record("Expected file path annotation event")
            return
        }
        #expect(pathAnnotation.fileId == "file_1")
        #expect(pathAnnotation.filename == "note.txt")
    }

    @Test func `annotation helpers reject invalid payloads`() {
        #expect(
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
            ) == nil
        )
        #expect(
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
            ) == nil
        )
    }

    @Test func `annotation type classification and substring extraction`() {
        #expect(OpenAIStreamEventTranslator.isFileCitationAnnotationType("file_path"))
        #expect(OpenAIStreamEventTranslator.isFileCitationAnnotationType("container_file_citation"))
        #expect(!OpenAIStreamEventTranslator.isFileCitationAnnotationType("url_citation"))

        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef", startIndex: 1, endIndex: 4
            ) == "bcd"
        )
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef", startIndex: 3, endIndex: 20
            ) == "def"
        )
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef", startIndex: -1, endIndex: 2
            ) == ""
        )
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abcdef", startIndex: 5, endIndex: 5
            ) == ""
        )
    }
}
