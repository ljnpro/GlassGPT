import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAITransportConfigurationTests {
    @Test func `default configuration provider ships bundled Cloudflare token`() {
        let provider = DefaultOpenAIConfigurationProvider()
        #expect(provider.cloudflareAIGToken == DefaultOpenAIConfigurationProvider.defaultCloudflareAIGToken)
        #expect(!provider.cloudflareAIGToken.isEmpty)
    }

    @Test func `default configuration provider tracks gateway toggle state`() {
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

    @Test func `models request uses configured gateway base URL`() throws {
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

    @Test(arguments: [
        OpenAIRequestAuthorizationCase(
            useCloudflareGateway: false,
            expectedCloudflareAuthorization: nil
        ),
        OpenAIRequestAuthorizationCase(
            useCloudflareGateway: true,
            expectedCloudflareAuthorization: "Bearer gateway-token"
        )
    ])
    func `request authorizer respects cloudflare authorization toggle`(
        _ testCase: OpenAIRequestAuthorizationCase
    ) throws {
        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: testCase.useCloudflareGateway
        )
        let url = try #require(URL(string: "https://example.com"))
        var request = URLRequest(url: url)
        OpenAIStandardRequestAuthorizer(configuration: config).applyAuthorization(
            to: &request,
            apiKey: "sk-test",
            includeCloudflareAuthorization: true
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "cf-aig-authorization") == testCase.expectedCloudflareAuthorization)
    }

    @Test func `transport session factory builds explicit request and download sessions`() {
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

    @Test func `open AIURL session transport cancels underlying request`() async throws {
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
            let isCancelledServiceError = if case .cancelled = error as? OpenAIServiceError {
                true
            } else {
                false
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
    @Test func `open AI service streams through injected stream client`() async {
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
    @Test func `open AI service upload uses injected transport`() async throws {
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

struct OpenAIRequestAuthorizationCase {
    let useCloudflareGateway: Bool
    let expectedCloudflareAuthorization: String?
}
