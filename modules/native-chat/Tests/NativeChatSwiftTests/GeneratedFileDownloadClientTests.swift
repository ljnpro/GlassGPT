import Foundation
import OpenAITransport
import Testing
@testable import GeneratedFilesInfra

struct GeneratedFileDownloadClientTests {
    @Test func `downloadFromAPI percent-encodes container and file identifiers in path segments`() async throws {
        let configuration = GeneratedFileDownloadTransportFixture(useCloudflareGateway: false)
        let transport = CapturingGeneratedFileTransport()
        let client = GeneratedFileDownloadClient(
            configurationProvider: configuration,
            requestAuthorizer: OpenAIStandardRequestAuthorizer(configuration: configuration),
            transport: transport
        )

        _ = try await client.downloadFromAPI(
            fileId: "file id/😀",
            containerId: "container/one two",
            apiKey: "sk-test"
        )

        let capturedURL = try #require(await transport.lastURL())
        #expect(
            capturedURL.absoluteString ==
                "https://api.openai.com/v1/containers/container%2Fone%20two/files/file%20id%2F%F0%9F%98%80/content"
        )
    }
}

private struct GeneratedFileDownloadTransportFixture: OpenAIConfigurationProvider {
    let directOpenAIBaseURL = "https://api.openai.com/v1"
    let cloudflareGatewayBaseURL = "https://gateway.example/v1"
    let cloudflareAIGToken = "gateway-token"
    var useCloudflareGateway: Bool
}

private actor CapturingGeneratedFileTransport: OpenAIDataTransport {
    private var capturedRequest: URLRequest?

    func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        capturedRequest = request
        guard let responseURL = request.url else {
            throw .invalidURL
        }
        guard let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw .requestFailed("Unable to construct generated file test response")
        }
        return (Data("file".utf8), response)
    }

    func lastURL() -> URL? {
        capturedRequest?.url
    }
}
