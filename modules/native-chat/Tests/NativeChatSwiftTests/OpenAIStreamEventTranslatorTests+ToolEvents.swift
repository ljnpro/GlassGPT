import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

extension OpenAIStreamEventTranslatorTests {
    @Test func translateRecognizesWebSearchLifecycleEvents() throws {
        assertTranslation(
            eventType: "response.web_search_call.in_progress",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case .webSearchStarted(let itemID) = event else {
                Issue.record("Expected web search started event")
                return
            }
            #expect(itemID == "ws_1")
        }

        assertTranslation(
            eventType: "response.web_search_call.searching",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case .webSearchSearching(let itemID) = event else {
                Issue.record("Expected web search searching event")
                return
            }
            #expect(itemID == "ws_1")
        }

        assertTranslation(
            eventType: "response.web_search_call.completed",
            envelope: makeEnvelope(itemID: "ws_1")
        ) { event in
            guard case .webSearchCompleted(let itemID) = event else {
                Issue.record("Expected web search completed event")
                return
            }
            #expect(itemID == "ws_1")
        }
    }

    @Test func translateRecognizesCodeInterpreterStartAndInterpretEvents() throws {
        assertTranslation(
            eventType: "response.code_interpreter_call.in_progress",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterStarted(let itemID) = event else {
                Issue.record("Expected code interpreter started event")
                return
            }
            #expect(itemID == "ci_1")
        }

        assertTranslation(
            eventType: "response.code_interpreter_call.interpreting",
            envelope: makeEnvelope(itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterInterpreting(let itemID) = event else {
                Issue.record("Expected code interpreter interpreting event")
                return
            }
            #expect(itemID == "ci_1")
        }
    }

    @Test func translateRecognizesCodeInterpreterCodeAndCompletionEvents() throws {
        assertTranslation(
            eventType: "response.code_interpreter_call_code.delta",
            envelope: makeEnvelope(delta: "print", itemID: "ci_1")
        ) { event in
            guard case .codeInterpreterCodeDelta(let itemID, let delta) = event else {
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
            guard case .codeInterpreterCodeDone(let itemID, let code) = event else {
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
            guard case .codeInterpreterCompleted(let itemID) = event else {
                Issue.record("Expected code interpreter completed event")
                return
            }
            #expect(itemID == "ci_1")
        }
    }

    @Test func translateRecognizesFileSearchLifecycleEvents() throws {
        assertTranslation(
            eventType: "response.file_search_call.in_progress",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case .fileSearchStarted(let itemID) = event else {
                Issue.record("Expected file search started event")
                return
            }
            #expect(itemID == "fs_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.searching",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case .fileSearchSearching(let itemID) = event else {
                Issue.record("Expected file search searching event")
                return
            }
            #expect(itemID == "fs_1")
        }

        assertTranslation(
            eventType: "response.file_search_call.completed",
            envelope: makeEnvelope(itemID: "fs_1")
        ) { event in
            guard case .fileSearchCompleted(let itemID) = event else {
                Issue.record("Expected file search completed event")
                return
            }
            #expect(itemID == "fs_1")
        }
    }

    @Test func translateHandlesCompletedTerminalEvent() throws {
        let terminalResponse = makeTerminalResponse()

        assertTranslation(
            eventType: "response.completed",
            envelope: makeEnvelope(response: terminalResponse)
        ) { event in
            guard case .completed(let text, let thinking, let annotations) = event else {
                Issue.record("Expected completed event")
                return
            }
            #expect(text == "sandbox:/tmp/report.txt")
            #expect(thinking == "plan summary")
            #expect(annotations?.first?.fileId == "file_terminal")
        }
    }

    @Test func translateHandlesIncompleteTerminalEvent() throws {
        let terminalResponse = makeTerminalResponse()

        assertTranslation(
            eventType: "response.incomplete",
            envelope: makeEnvelope(response: terminalResponse)
        ) { event in
            guard case .incomplete(let text, let thinking, let annotations, let message) = event else {
                Issue.record("Expected incomplete event")
                return
            }
            #expect(text == "sandbox:/tmp/report.txt")
            #expect(thinking == "plan summary")
            #expect(annotations?.first?.filename == "report.txt")
            #expect(message == "needs recovery")
        }
    }

    @Test func translateHandlesStreamAndResponseErrorEvents() throws {
        assertTranslation(
            eventType: "error",
            envelope: makeEnvelope(message: "stream exploded")
        ) { event in
            guard case .error(let error) = event else {
                Issue.record("Expected error event")
                return
            }
            #expect(error.errorDescription == "stream exploded")
        }

        assertTranslation(
            eventType: "response.failed",
            envelope: makeEnvelope()
        ) { event in
            guard case .error(let error) = event else {
                Issue.record("Expected failed event to map to error")
                return
            }
            #expect(error.errorDescription == "Response generation failed.")
        }
    }

    @Test func extractionHelpersPreferStructuredContent() {
        let response = makeStructuredExtractionResponse()

        #expect(OpenAIStreamEventTranslator.extractOutputText(from: response) == "top level text")
        #expect(
            OpenAIStreamEventTranslator.extractReasoningText(from: response)
                == "top levelplan summary step"
        )
        #expect(OpenAIStreamEventTranslator.extractErrorMessage(from: response) == "structured")
    }

    @Test func extractionHelpersGracefullyHandleEdgeCases() {
        let response = makeStructuredExtractionResponse()

        let annotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: response)
        #expect(annotations.count == 1)
        #expect(annotations.first?.sandboxPath == "body")
    }

    @Test func annotationHelpersValidateURLPayloads() {
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

        guard case .annotationAdded(let citation) = OpenAIStreamEventTranslator.annotationEvent(
            from: urlAnnotation
        ) else {
            Issue.record("Expected URL citation event")
            return
        }
        #expect(citation.startIndex == 1)
        #expect(citation.endIndex == 4)
    }

    @Test func annotationHelpersValidateFilePayloads() {
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

        guard case .filePathAnnotationAdded(let pathAnnotation) = OpenAIStreamEventTranslator.annotationEvent(
            from: fileAnnotation
        ) else {
            Issue.record("Expected file path annotation event")
            return
        }
        #expect(pathAnnotation.fileId == "file_1")
        #expect(pathAnnotation.filename == "note.txt")
    }

    @Test func annotationHelpersRejectInvalidPayloads() {
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

    @Test func annotationTypeClassificationAndSubstringExtraction() {
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
