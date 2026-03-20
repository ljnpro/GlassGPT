import OpenAITransport
import XCTest

final class OpenAITransportSourceTests: XCTestCase {
    func testModelsRequestUsesConfiguredRouteAndHeaders() throws {
        let configuration = TransportFixture(useCloudflareGateway: true)
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.modelsRequest(apiKey: "sk-test")

        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-authorization"), "Bearer gateway-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testCancelRequestCanForceDirectRouteAndUsesEmptyBody() throws {
        let configuration = TransportFixture(useCloudflareGateway: true)
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.cancelRequest(
            responseID: "resp_123",
            apiKey: "sk-test",
            useDirectBaseURL: true
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses/resp_123/cancel")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(request.httpBody, Data())
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "cf-aig-authorization"))
    }

    func testFetchRequestIncludesDefaultExpansionQueryItems() throws {
        let configuration = TransportFixture(useCloudflareGateway: false)
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.fetchRequest(responseID: "resp_123", apiKey: "sk-test")
        let urlString = try XCTUnwrap(request.url?.absoluteString)

        XCTAssertTrue(urlString.hasPrefix("https://api.openai.com/v1/responses/resp_123?"))
        XCTAssertTrue(urlString.contains("include%5B%5D=code_interpreter_call.outputs"))
        XCTAssertTrue(urlString.contains("include%5B%5D=file_search_call.results"))
        XCTAssertTrue(urlString.contains("include%5B%5D=web_search_call.action.sources"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testFetchRequestPercentEncodesDynamicResponseIdentifierInPath() throws {
        let configuration = TransportFixture(useCloudflareGateway: false)
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.fetchRequest(
            responseID: "resp folder/🧪?#",
            apiKey: "sk-test"
        )
        let urlString = try XCTUnwrap(request.url?.absoluteString)

        XCTAssertTrue(
            urlString.hasPrefix(
                "https://api.openai.com/v1/responses/resp%20folder%2F%F0%9F%A7%AA%3F%23?"
            )
        )
    }

    func testUploadRequestBuildsMultipartBodyAndMimeType() throws {
        let configuration = TransportFixture(useCloudflareGateway: true)
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.uploadRequest(
            fileData: Data("hello".utf8),
            filename: "notes.md",
            apiKey: "sk-test",
            boundary: "Boundary-UnitTest"
        )
        let body = try XCTUnwrap(request.httpBody).stringValue

        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/files")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 120)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-UnitTest"
        )
        XCTAssertTrue(body.contains("name=\"purpose\""))
        XCTAssertTrue(body.contains("user_data"))
        XCTAssertTrue(body.contains("filename=\"notes.md\""))
        XCTAssertTrue(body.contains("Content-Type: text/plain"))
        XCTAssertTrue(body.contains("hello"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-authorization"), "Bearer gateway-token")
    }

    func testUploadRequestEscapesMultipartFilenameHeader() throws {
        let configuration = TransportFixture(useCloudflareGateway: true)
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.uploadRequest(
            fileData: Data("hello".utf8),
            filename: "report\"\r\nX-Injected: 1.txt",
            apiKey: "sk-test",
            boundary: "Boundary-UnitTest"
        )
        let body = try XCTUnwrap(request.httpBody).stringValue

        XCTAssertTrue(body.contains("filename=\"report\\\" X-Injected: 1.txt\""))
        XCTAssertFalse(body.contains("filename=\"report\"\r\nX-Injected: 1.txt\""))
    }

    func testMimeTypeFallsBackToOctetStreamForUnknownExtension() {
        XCTAssertEqual(OpenAIRequestFactory.mimeType(for: "archive.custom"), "application/octet-stream")
        XCTAssertEqual(OpenAIRequestFactory.mimeType(for: "photo.jpeg"), "image/jpeg")
        XCTAssertEqual(OpenAIRequestFactory.mimeType(for: "report.pdf"), "application/pdf")
    }

    func testSSEFrameBufferFinishPendingFramesFlushesTrailingPayloadWithoutTerminalBlankLine() {
        var buffer = SSEFrameBuffer()

        XCTAssertEqual(buffer.append("event: response.output_text.delta\ndata: Hel"), [])
        let frames = buffer.finishPendingFrames()

        XCTAssertEqual(
            frames,
            [SSEFrame(type: "response.output_text.delta", data: "Hel")]
        )
    }
}

private struct TransportFixture: OpenAIConfigurationProvider {
    let directOpenAIBaseURL = "https://api.openai.com/v1"
    let cloudflareGatewayBaseURL = "https://gateway.example/v1"
    let cloudflareAIGToken = "gateway-token"
    var useCloudflareGateway: Bool
}

private extension Data {
    var stringValue: String {
        String(decoding: self, as: UTF8.self)
    }
}
