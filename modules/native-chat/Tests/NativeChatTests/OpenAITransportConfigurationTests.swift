import XCTest
@testable import NativeChat

final class OpenAITransportConfigurationTests: XCTestCase {
    func testDefaultConfigurationProviderTracksGatewayToggleThroughSettingsStore() {
        let valueStore = InMemorySettingsValueStore()
        let settingsStore = SettingsStore(valueStore: valueStore)
        let provider = DefaultOpenAIConfigurationProvider(settingsStore: settingsStore)

        XCTAssertEqual(provider.directOpenAIBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(provider.openAIBaseURL, "https://api.openai.com/v1")

        provider.useCloudflareGateway = true

        XCTAssertTrue(settingsStore.cloudflareGatewayEnabled)
        XCTAssertEqual(provider.openAIBaseURL, provider.cloudflareGatewayBaseURL)
    }

    func testModelsRequestUsesConfiguredGatewayBaseURL() throws {
        let config = TransportConfigurationFixture(
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
        let config = TransportConfigurationFixture(
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

    func testRequestAuthorizerAddsCloudflareAuthorizationWhenRequestedAndEnabled() {
        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        var request = URLRequest(url: URL(string: "https://example.com")!)

        OpenAIStandardRequestAuthorizer(configuration: config).applyAuthorization(
            to: &request,
            apiKey: "sk-test",
            includeCloudflareAuthorization: true
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "cf-aig-authorization"),
            "Bearer gateway-token"
        )
    }

    @MainActor
    func testOpenAIServiceStreamsThroughInjectedStreamClient() async {
        let streamClient = RecordingOpenAIStreamClient()
        let transport = MockOpenAIDataTransport()
        let config = TransportConfigurationFixture(
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
            model: ModelType.gpt5_4,
            reasoningEffort: ReasoningEffort.none,
            backgroundModeEnabled: false,
            serviceTier: ServiceTier.standard
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

        let config = TransportConfigurationFixture(
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

    @MainActor
    func testOpenAIServiceFetchResponseFallsBackToDirectRouteAfterGatewayFailure() async throws {
        let transport = MockOpenAIDataTransport()
        transport.queuedErrors = [URLError(.cannotConnectToHost)]
        transport.queuedResponses = [
            (
                try JSONCoding.encode(
                    ResponsesResponseDTO(
                        status: "completed",
                        output: [
                            ResponsesOutputItemDTO(
                                type: "message",
                                id: nil,
                                content: [
                                    ResponsesContentPartDTO(
                                        type: "output_text",
                                        text: "Recovered text",
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
                        ]
                    )
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.openai.com/v1/responses/resp_123")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        ]

        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        let service = OpenAIService(
            requestBuilder: OpenAIRequestBuilder(configuration: config),
            transport: transport
        )

        let result = try await service.fetchResponse(responseId: "resp_123", apiKey: "sk-test")

        XCTAssertEqual(result.status, OpenAIResponseFetchResult.Status.completed)
        XCTAssertEqual(result.text, "Recovered text")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            transport.requests.first?.url?.host,
            "gateway.example"
        )
        XCTAssertEqual(
            transport.requests.last?.url?.host,
            "api.openai.com"
        )
        XCTAssertEqual(
            transport.requests.first?.value(forHTTPHeaderField: "cf-aig-authorization"),
            "Bearer gateway-token"
        )
        XCTAssertNil(transport.requests.last?.value(forHTTPHeaderField: "cf-aig-authorization"))
    }

    @MainActor
    func testOpenAIServiceCancelResponseFallsBackToDirectRouteAfterGatewayFailure() async throws {
        let transport = MockOpenAIDataTransport()
        transport.queuedErrors = [URLError(.networkConnectionLost)]
        transport.queuedResponses = [
            (
                Data(),
                HTTPURLResponse(
                    url: URL(string: "https://api.openai.com/v1/responses/resp_123/cancel")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        ]

        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        let service = OpenAIService(
            requestBuilder: OpenAIRequestBuilder(configuration: config),
            transport: transport
        )

        try await service.cancelResponse(responseId: "resp_123", apiKey: "sk-test")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.first?.url?.host, "gateway.example")
        XCTAssertEqual(transport.requests.last?.url?.host, "api.openai.com")
    }

    @MainActor
    func testOpenAIServiceValidateAPIKeyReturnsFalseWhenTransportFails() async {
        let transport = MockOpenAIDataTransport()
        transport.queuedErrors = [URLError(.notConnectedToInternet)]

        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: false
        )
        let service = OpenAIService(
            requestBuilder: OpenAIRequestBuilder(configuration: config),
            transport: transport
        )

        let isValid = await service.validateAPIKey("sk-test")

        XCTAssertFalse(isValid)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://api.openai.com/v1/models")
    }

    @MainActor
    func testOpenAIServiceGenerateTitleUsesParsedResponseText() async throws {
        let transport = MockOpenAIDataTransport()
        transport.queuedResponses = [
            (
                try JSONCoding.encode(
                    ResponsesResponseDTO(
                        output: [
                            ResponsesOutputItemDTO(
                                type: "message",
                                id: nil,
                                content: [
                                    ResponsesContentPartDTO(
                                        type: "output_text",
                                        text: "\"Release readiness review plan\"",
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
                        ]
                    )
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.openai.com/v1/responses")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        ]

        let service = OpenAIService(transport: transport)

        let title = try await service.generateTitle(
            for: "Please summarize the release readiness plan",
            apiKey: "sk-test"
        )

        XCTAssertEqual(title, "Release readiness review plan")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.httpMethod, "POST")
    }
}

private final class MockOpenAIDataTransport: OpenAIDataTransport, @unchecked Sendable {
    private(set) var requestCalled = false
    private(set) var lastRequest: URLRequest?
    private(set) var requests: [URLRequest] = []

    var nextResponseData = Data("{}".utf8)
    var nextResponse: HTTPURLResponse?
    var queuedResponses: [(Data, HTTPURLResponse)] = []
    var queuedErrors: [Error] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCalled = true
        lastRequest = request
        requests.append(request)

        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }

        if !queuedResponses.isEmpty {
            let next = queuedResponses.removeFirst()
            return next
        }

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

private struct TransportConfigurationFixture: OpenAIConfigurationProvider {
    let directOpenAIBaseURL: String
    let cloudflareGatewayBaseURL: String
    let cloudflareAIGToken: String
    var useCloudflareGateway: Bool

    var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : directOpenAIBaseURL
    }
}
