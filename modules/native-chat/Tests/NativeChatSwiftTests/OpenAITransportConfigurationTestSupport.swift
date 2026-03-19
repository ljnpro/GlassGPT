import ChatDomain
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

final class MockOpenAIDataTransport: OpenAIDataTransport, @unchecked Sendable {
    private(set) var requestCalled = false
    private(set) var lastRequest: URLRequest?
    private(set) var requests: [URLRequest] = []

    var nextResponseData = Data("{}".utf8)
    var nextResponse: HTTPURLResponse?
    var queuedResponses: [(Data, HTTPURLResponse)] = []
    var queuedErrors: [Error] = []

    func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        requestCalled = true
        lastRequest = request
        requests.append(request)

        if !queuedErrors.isEmpty {
            let error = queuedErrors.removeFirst()
            if let serviceError = error as? OpenAIServiceError {
                throw serviceError
            }
            throw .requestFailed(error.localizedDescription)
        }

        if !queuedResponses.isEmpty {
            return queuedResponses.removeFirst()
        }

        if let nextResponse {
            return (nextResponseData, nextResponse)
        }

        let fallbackURL = request.url ?? URL(string: "https://api.openai.com")
        let fallback = HTTPURLResponse(
            url: fallbackURL ?? URL(fileURLWithPath: "/"),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        return (nextResponseData, fallback ?? URLResponse())
    }
}

final class RecordingOpenAIStreamClient: OpenAIStreamClient {
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

struct TransportConfigurationFixture: OpenAIConfigurationProvider {
    let directOpenAIBaseURL: String
    let cloudflareGatewayBaseURL: String
    let cloudflareAIGToken: String
    var useCloudflareGateway: Bool

    var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : directOpenAIBaseURL
    }
}

final class CancellationAwareURLProtocol: URLProtocol {
    static let state = CancellationAwareURLProtocolState()

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.recordStart()
    }

    override func stopLoading() {
        Self.state.recordCancellation()
    }
}

final class CancellationAwareURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var didCancel = false
    private var semaphore = DispatchSemaphore(value: 0)

    func reset() {
        lock.lock()
        didCancel = false
        semaphore = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func recordStart() {}

    func recordCancellation() {
        lock.lock()
        guard !didCancel else {
            lock.unlock()
            return
        }
        didCancel = true
        let semaphore = semaphore
        lock.unlock()
        semaphore.signal()
    }

    func waitForCancellation(timeout: TimeInterval) -> Bool {
        lock.lock()
        if didCancel {
            lock.unlock()
            return true
        }
        let semaphore = semaphore
        lock.unlock()
        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}

// MARK: - Gateway Test Helpers

enum GatewayTestHelpers {
    static func makeGatewayFallbackTransport(
        queuedError: Error,
        responseText: String,
        responseURL: String
    ) throws -> MockOpenAIDataTransport {
        let transport = MockOpenAIDataTransport()
        transport.queuedErrors = [queuedError]
        let url = try #require(URL(string: responseURL))
        let httpResponse = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        transport.queuedResponses = try [
            (
                JSONCoding.encode(
                    ResponsesResponseDTO(
                        status: "completed",
                        output: [
                            ResponsesOutputItemDTO(
                                type: "message",
                                id: nil,
                                content: [
                                    ResponsesContentPartDTO(
                                        type: "output_text",
                                        text: responseText,
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
        return transport
    }

    @MainActor static func makeGatewayService(transport: MockOpenAIDataTransport) -> OpenAIService {
        let config = TransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        return OpenAIService(
            requestBuilder: OpenAIRequestBuilder(configuration: config),
            transport: transport
        )
    }

    static func assertGatewayFallbackRequests(_ transport: MockOpenAIDataTransport) {
        #expect(transport.requests.count == 2)
        #expect(transport.requests.first?.url?.host == "gateway.example")
        #expect(transport.requests.last?.url?.host == "api.openai.com")
        #expect(
            transport.requests.first?.value(forHTTPHeaderField: "cf-aig-authorization")
                == "Bearer gateway-token"
        )
        #expect(transport.requests.last?.value(forHTTPHeaderField: "cf-aig-authorization") == nil)
    }
}
