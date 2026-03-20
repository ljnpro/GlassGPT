import ChatDomain
import Foundation
import OpenAITransport
import Testing
@testable import GeneratedFilesInfra

struct OpenAITransportTimeoutTests {
    @Test func `streaming request uses configurable chat timeout`() throws {
        let configuration = TimeoutConfigurationFixture(
            chatRequestTimeoutInterval: 42,
            generatedFileDownloadTimeoutInterval: 17
        )
        let factory = OpenAIRequestFactory(configuration: configuration)

        let request = try factory.streamingRequest(
            apiKey: "sk-test",
            messages: [],
            model: .gpt5_4,
            reasoningEffort: .none,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )

        #expect(request.timeoutInterval == 42)
    }

    @Test func `generated file downloads use configurable timeout`() async throws {
        let configuration = TimeoutConfigurationFixture(
            chatRequestTimeoutInterval: 42,
            generatedFileDownloadTimeoutInterval: 17
        )
        let transport = TimeoutCapturingGeneratedFileTransport()
        let client = GeneratedFileDownloadClient(
            configurationProvider: configuration,
            requestAuthorizer: OpenAIStandardRequestAuthorizer(configuration: configuration),
            transport: transport
        )

        _ = try await client.downloadFromAPI(
            fileId: "file_123",
            containerId: nil,
            apiKey: "sk-test"
        )

        #expect(await transport.lastTimeoutInterval() == 17)
    }
}

private struct TimeoutConfigurationFixture: OpenAIConfigurationProvider {
    let directOpenAIBaseURL = "https://api.openai.com/v1"
    let cloudflareGatewayBaseURL = "https://gateway.example/v1"
    let cloudflareAIGToken = "gateway-token"
    var useCloudflareGateway = false
    let chatRequestTimeoutInterval: TimeInterval
    let generatedFileDownloadTimeoutInterval: TimeInterval
}

private actor TimeoutCapturingGeneratedFileTransport: OpenAIDataTransport {
    private var timeoutInterval: TimeInterval?

    func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        timeoutInterval = request.timeoutInterval
        guard let responseURL = request.url else {
            throw .invalidURL
        }
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) ?? HTTPURLResponse()
        return (Data("file".utf8), response)
    }

    func lastTimeoutInterval() -> TimeInterval? {
        timeoutInterval
    }
}
