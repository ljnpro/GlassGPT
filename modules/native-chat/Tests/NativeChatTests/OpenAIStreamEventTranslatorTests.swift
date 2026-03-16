import XCTest
@testable import NativeChat

final class OpenAIStreamEventTranslatorTests: XCTestCase {
    func testTranslateRecognizesResponseCreatedAndTextDelta() {
        let created = OpenAIStreamEventTranslator.translate(
            eventType: "response.created",
            data: ["response": ["id": "resp_123"]]
        )
        let delta = OpenAIStreamEventTranslator.translate(
            eventType: "response.output_text.delta",
            data: ["delta": "Hi"]
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

    func testExtractFilePathAnnotationsUsesAnnotatedSubstring() {
        let text = "sandbox:/mnt/data/report.pdf"
        let annotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: [
            "output": [[
                "type": "message",
                "content": [[
                    "type": "output_text",
                    "text": text,
                    "annotations": [[
                        "type": "file_path",
                        "file_id": "file_report",
                        "container_id": "container_123",
                        "filename": "report.pdf",
                        "start_index": 0,
                        "end_index": text.count
                    ]]
                ]]
            ]]
        ])

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
}
