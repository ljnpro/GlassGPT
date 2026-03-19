import ChatPersistenceCore
import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAITransportConfigurationTests {
    @Test func defaultConfigurationProviderTracksGatewayToggleState() {
        let provider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: false
        )

        #expect(provider.directOpenAIBaseURL == "https://api.openai.com/v1")
        #expect(provider.openAIBaseURL == "https://api.openai.com/v1")

        provider.useCloudflareGateway = true

        #expect(provider.useCloudflareGateway)
        #expect(provider.openAIBaseURL == provider.cloudflareGatewayBaseURL)
    }

    @Test func modelsRequestUsesConfiguredGatewayBaseURL() throws {
        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        let requestBuilder = OpenAIRequestBuilder(configuration: config)

        let request = try requestBuilder.modelsRequest(apiKey: "sk-test")

        #expect(request.url?.absoluteString == "https://gateway.example/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer gateway-token")
    }

    @Test func requestAuthorizerCanSkipCloudflareAuthorizationWhenDisabled() throws {
        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: false
        )
        let url = try #require(URL(string: "https://example.com"))
        var request = URLRequest(url: url)

        OpenAIStandardRequestAuthorizer(configuration: config).applyAuthorization(
            to: &request,
            apiKey: "sk-test",
            includeCloudflareAuthorization: true
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "cf-aig-authorization") == nil)
    }

    @Test func requestAuthorizerAddsCloudflareAuthorizationWhenRequestedAndEnabled() throws {
        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        let url = try #require(URL(string: "https://example.com"))
        var request = URLRequest(url: url)

        OpenAIStandardRequestAuthorizer(configuration: config).applyAuthorization(
            to: &request,
            apiKey: "sk-test",
            includeCloudflareAuthorization: true
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(
            request.value(forHTTPHeaderField: "cf-aig-authorization")
                == "Bearer gateway-token"
        )
    }

    @Test func transportSessionFactoryBuildsExplicitRequestAndDownloadSessions() {
        let requestSession = OpenAITransportSessionFactory.makeRequestSession()
        let downloadSession = OpenAITransportSessionFactory.makeDownloadSession()

        #expect(requestSession.configuration.timeoutIntervalForRequest == 60)
        #expect(requestSession.configuration.timeoutIntervalForResource == 120)
        #expect(requestSession.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(requestSession.configuration.urlCache == nil)
        #expect(!requestSession.configuration.waitsForConnectivity)

        #expect(downloadSession.configuration.timeoutIntervalForRequest == 120)
        #expect(downloadSession.configuration.timeoutIntervalForResource == 300)
        #expect(downloadSession.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(downloadSession.configuration.urlCache == nil)
        #expect(!downloadSession.configuration.waitsForConnectivity)
    }

    @Test func openAIURLSessionTransportCancelsUnderlyingRequest() async throws {
        CancellationAwareURLProtocol.state.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationAwareURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transport = OpenAIURLSessionTransport(session: session)
        let url = try #require(URL(string: "https://example.com/cancel"))
        let request = URLRequest(url: url)

        let task = Task {
            try await transport.data(for: request)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            let isCancelledServiceError: Bool
            if case .cancelled = error as? OpenAIServiceError {
                isCancelledServiceError = true
            } else {
                isCancelledServiceError = false
            }
            let isExpected = error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || isCancelledServiceError
            #expect(isExpected)
        }

        #expect(CancellationAwareURLProtocol.state.waitForCancellation(timeout: 1))
        session.invalidateAndCancel()
    }

    @MainActor
    @Test func openAIServiceStreamsThroughInjectedStreamClient() async {
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

        #expect(streamClient.lastRequest != nil)
        #expect(gotEvent)
        #expect(transport.lastRequest == nil)
        #expect(!transport.requestCalled)
        #expect(streamClient.lastRequest?.url?.absoluteString == "https://api.openai.com/v1/responses")
    }

    @MainActor
    @Test func openAIServiceUploadUsesInjectedTransport() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: ["id": "file_123"])
        let transport = MockOpenAIDataTransport()
        transport.nextResponseData = responseData
        let filesURL = try #require(URL(string: "https://api.openai.com/v1/files"))
        transport.nextResponse = try #require(HTTPURLResponse(
            url: filesURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))

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

        #expect(fileId == "file_123")
        #expect(
            transport.lastRequest?.url?.absoluteString
                == "https://api.openai.com/v1/files"
        )
        #expect(
            transport.lastRequest?.value(forHTTPHeaderField: "Authorization")
                == "Bearer sk-test"
        )
    }
}

// MARK: - Gateway Fallback & Validation Tests

extension OpenAITransportConfigurationTests {

    @MainActor
    @Test func openAIServiceFetchResponseFallsBackToDirectRouteAfterGatewayFailure() async throws {
        let transport = try GatewayTestHelpers.makeGatewayFallbackTransport(
            queuedError: URLError(.cannotConnectToHost),
            responseText: "Recovered text",
            responseURL: "https://api.openai.com/v1/responses/resp_123"
        )
        let service = GatewayTestHelpers.makeGatewayService(transport: transport)

        let result = try await service.fetchResponse(responseId: "resp_123", apiKey: "sk-test")

        #expect(result.status == OpenAIResponseFetchResult.Status.completed)
        #expect(result.text == "Recovered text")
        GatewayTestHelpers.assertGatewayFallbackRequests(transport)
    }

    @MainActor
    @Test func openAIServiceCancelResponseFallsBackToDirectRouteAfterGatewayFailure() async throws {
        let transport = MockOpenAIDataTransport()
        transport.queuedErrors = [URLError(.networkConnectionLost)]
        let cancelURL = try #require(
            URL(string: "https://api.openai.com/v1/responses/resp_123/cancel")
        )
        let cancelResponse = try #require(HTTPURLResponse(
            url: cancelURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        transport.queuedResponses = [(Data(), cancelResponse)]

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

        #expect(transport.requests.count == 2)
        #expect(transport.requests.first?.url?.host == "gateway.example")
        #expect(transport.requests.last?.url?.host == "api.openai.com")
    }

    @MainActor
    @Test func openAIServiceValidateAPIKeyReturnsFalseWhenTransportFails() async {
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

        #expect(!isValid)
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url?.absoluteString == "https://api.openai.com/v1/models")
    }

    @MainActor
    @Test func openAIServiceGenerateTitleUsesParsedResponseText() async throws {
        let transport = MockOpenAIDataTransport()
        let responsesURL = try #require(URL(string: "https://api.openai.com/v1/responses"))
        let httpResponse = try #require(HTTPURLResponse(
            url: responsesURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
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
                httpResponse
            )
        ]

        let service = OpenAIService(transport: transport)

        let title = try await service.generateTitle(
            for: "Please summarize the release readiness plan",
            apiKey: "sk-test"
        )

        #expect(title == "Release readiness review plan")
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.httpMethod == "POST")
    }

}
