import XCTest
@testable import NativeChat

final class OpenAITransportConfigurationTests: XCTestCase {
    func testModelsRequestUsesConfiguredGatewayBaseURL() throws {
        let config = TestOpenAIConfigurationProvider(
            openAIBaseURL: "https://gateway.example/v1",
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        let requestBuilder = OpenAIRequestBuilder(configuration: config)

        let request = try requestBuilder.modelsRequest(apiKey: "sk-test")

        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-authorization"), "Bearer gateway-token")
    }

    func testRequestAuthorizerCanSkipCloudflareAuthorizationWhenDisabled() throws {
        let config = TestOpenAIConfigurationProvider(
            openAIBaseURL: "https://api.openai.com/v1",
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: false
        )
        var request = URLRequest(url: URL(string: "https://example.com")!)

        OpenAIStandardRequestAuthorizer(configuration: config).applyAuthorization(
            to: &request,
            apiKey: "sk-test",
            includeCloudflareAuthorization: true
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "cf-aig-authorization"))
    }

    @MainActor
    func testOpenAIServiceStreamsThroughInjectedStreamClient() async {
        let streamClient = RecordingOpenAIStreamClient()
        let transport = MockOpenAIDataTransport()
        let config = TestOpenAIConfigurationProvider(
            openAIBaseURL: "https://api.openai.com/v1",
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: false
        )
        let service = OpenAIService(
            requestBuilder: OpenAIRequestBuilder(configuration: config),
            streamClient: streamClient,
            transport: transport
        )
        let stream = service.streamChat(
            apiKey: "sk-test",
            messages: [],
            model: .gpt5_4,
            reasoningEffort: .none,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )

        var gotEvent = false
        for await event in stream {
            if case .textDelta("ok") = event {
                gotEvent = true
                break
            }
        }

        XCTAssertTrue(streamClient.lastRequest != nil)
        XCTAssertTrue(gotEvent)
        XCTAssertNil(transport.lastRequest)
        XCTAssertFalse(transport.requestCalled)
        XCTAssertEqual(streamClient.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/responses")
    }

    @MainActor
    func testOpenAIServiceUploadUsesInjectedTransport() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: ["id": "file_123"])
        let transport = MockOpenAIDataTransport()
        transport.nextResponseData = responseData
        transport.nextResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/files")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let config = TestOpenAIConfigurationProvider(
            openAIBaseURL: "https://api.openai.com/v1",
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: false
        )

        let service = OpenAIService(
            requestBuilder: OpenAIRequestBuilder(configuration: config),
            transport: transport
        )

        let fileId = try await service.uploadFile(
            data: Data([0x00]),
            filename: "x.txt",
            apiKey: "sk-test"
        )

        XCTAssertEqual(fileId, "file_123")
        XCTAssertEqual(
            transport.lastRequest?.url?.absoluteString,
            "https://api.openai.com/v1/files"
        )
        XCTAssertEqual(
            transport.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer sk-test"
        )
    }
}

private final class MockOpenAIDataTransport: OpenAIDataTransport, @unchecked Sendable {
    private(set) var requestCalled = false
    private(set) var lastRequest: URLRequest?

    var nextResponseData = Data("{}".utf8)
    var nextResponse: HTTPURLResponse?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCalled = true
        lastRequest = request
        if let nextResponse {
            return (nextResponseData, nextResponse)
        }

        let fallback = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.openai.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (nextResponseData, fallback)
    }
}

private final class RecordingOpenAIStreamClient: OpenAIStreamClient {
    private(set) var lastRequest: URLRequest?

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        lastRequest = request
        return AsyncStream { continuation in
            continuation.yield(.textDelta("ok"))
            continuation.finish()
        }
    }

    func cancel() {}
}

private struct TestOpenAIConfigurationProvider: OpenAIConfigurationProvider {
    let openAIBaseURL: String
    let directOpenAIBaseURL: String
    let cloudflareGatewayBaseURL: String
    let cloudflareAIGToken: String
    var useCloudflareGateway: Bool
}
