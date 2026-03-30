import BackendAuth
import BackendContracts
import BackendSessionPersistence
import ChatPersistenceCore
import Foundation
@testable import BackendClient

func makeConnectionCheckResponseData() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "backend": "healthy",
        "auth": "healthy",
        "openaiCredential": "healthy",
        "sse": "healthy",
        "checkedAt": "1970-01-01T00:00:00Z",
        "latencyMilliseconds": 12,
        "backendVersion": "5.4.0",
        "minimumSupportedAppVersion": "5.3.0",
        "appCompatibility": "compatible"
    ])
}

func makeSessionResponseData(
    accessToken: String,
    refreshToken: String,
    expiresAt: String
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "accessToken": accessToken,
        "refreshToken": refreshToken,
        "expiresAt": expiresAt,
        "deviceId": "device_01",
        "user": [
            "id": "usr_01",
            "appleSubject": "apple-subject-01",
            "email": "glass@example.com",
            "displayName": "Glass User",
            "createdAt": "1970-01-01T00:00:00Z"
        ]
    ])
}

func makeSessionDTO(
    accessToken: String = "access-token",
    refreshToken: String = "refresh-token",
    expiresAt: String = "2100-01-01T00:16:40Z"
) throws -> SessionDTO {
    let data = try makeSessionResponseData(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SessionDTO.self, from: data)
}

final class RecordingBackendURLProtocol: URLProtocol {
    static let state = RecordingBackendURLProtocolState()

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.recordRequest(request)
        if let configuredFailure = Self.state.dequeueFailure() {
            client?.urlProtocol(self, didFailWithError: configuredFailure)
            return
        }
        guard let responseURL = request.url ?? URL(string: "https://example.com") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let configuredResponse = Self.state.dequeueResponse()
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: configuredResponse.responseStatusCode,
            httpVersion: nil,
            headerFields: configuredResponse.responseHeaders
        )
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: configuredResponse.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RecordingBackendURLProtocolState: @unchecked Sendable {
    enum StubbedResult {
        case failure(URLError)
        case response(StubbedResponse)
    }

    struct StubbedResponse {
        let responseStatusCode: Int
        let responseBody: Data
        let responseHeaders: [String: String]
    }

    struct RecordedRequest: Equatable {
        let path: String
        let query: String?
        let authorizationHeader: String?
        let appVersionHeader: String?
        let lastEventIDHeader: String?
    }

    struct Snapshot {
        let lastAuthorizationHeader: String?
        let recordedRequests: [RecordedRequest]
    }

    private let lock = NSLock()
    private var resultQueue: [StubbedResult] = []
    private var recordedRequests: [RecordedRequest] = []

    func reset() {
        lock.lock()
        resultQueue.removeAll()
        recordedRequests.removeAll()
        lock.unlock()
    }

    func enqueueResponse(
        responseStatusCode: Int,
        responseBody: Data,
        responseHeaders: [String: String] = ["Content-Type": "application/json"]
    ) {
        lock.lock()
        resultQueue.append(
            .response(
                StubbedResponse(
                    responseStatusCode: responseStatusCode,
                    responseBody: responseBody,
                    responseHeaders: responseHeaders
                )
            )
        )
        lock.unlock()
    }

    func enqueueFailure(_ error: URLError) {
        lock.lock()
        resultQueue.append(.failure(error))
        lock.unlock()
    }

    func dequeueFailure() -> URLError? {
        lock.lock()
        defer { lock.unlock() }

        guard let first = resultQueue.first else {
            return nil
        }

        guard case let .failure(error) = first else {
            return nil
        }

        resultQueue.removeFirst()
        return error
    }

    func dequeueResponse() -> StubbedResponse {
        lock.lock()
        defer { lock.unlock() }

        guard !resultQueue.isEmpty else {
            return StubbedResponse(
                responseStatusCode: 200,
                responseBody: Data(),
                responseHeaders: ["Content-Type": "application/json"]
            )
        }

        let result = resultQueue.removeFirst()
        switch result {
        case let .response(response):
            return response
        case .failure:
            return StubbedResponse(
                responseStatusCode: 200,
                responseBody: Data(),
                responseHeaders: ["Content-Type": "application/json"]
            )
        }
    }

    func recordRequest(_ request: URLRequest) {
        lock.lock()
        recordedRequests.append(
            RecordedRequest(
                path: request.url?.path ?? "",
                query: request.url?.query,
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization"),
                appVersionHeader: request.value(forHTTPHeaderField: backendAppVersionHeaderField),
                lastEventIDHeader: request.value(forHTTPHeaderField: "Last-Event-ID")
            )
        )
        lock.unlock()
    }

    var snapshot: Snapshot {
        lock.lock()
        let snapshot = Snapshot(
            lastAuthorizationHeader: recordedRequests.last?.authorizationHeader,
            recordedRequests: recordedRequests
        )
        lock.unlock()
        return snapshot
    }
}

@MainActor
func withDeterministicRetryPolicy(
    _ operation: () async throws -> Void
) async throws {
    let originalJitterProvider = BackendRetryPolicy.jitterProvider
    let originalSleepImplementation = BackendRetryPolicy.sleepImplementation
    BackendRetryPolicy.jitterProvider = { 0 }
    BackendRetryPolicy.sleepImplementation = { _ in }
    defer {
        BackendRetryPolicy.jitterProvider = originalJitterProvider
        BackendRetryPolicy.sleepImplementation = originalSleepImplementation
    }
    try await operation()
}

final class InMemoryAPIKeyBackend: @unchecked Sendable, APIKeyPersisting {
    private var storedKey: String?
    private(set) var didDelete = false

    func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        storedKey = apiKey
    }

    func loadAPIKey() -> String? {
        storedKey
    }

    func deleteAPIKey() {
        didDelete = true
        storedKey = nil
    }
}
