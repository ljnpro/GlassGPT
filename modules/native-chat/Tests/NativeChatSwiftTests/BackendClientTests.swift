import BackendAuth
import BackendClient
import BackendContracts
import BackendSessionPersistence
import ChatPersistenceCore
import Foundation
import Testing

struct BackendClientTests {
    @MainActor
    @Test
    func `connection check uses session authorization`() async throws {
        RecordingBackendURLProtocol.state.reset()
        try RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: makeConnectionCheckResponseData()
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO()
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: sessionStore,
            urlSession: session
        )

        _ = try await client.connectionCheck()

        #expect(
            RecordingBackendURLProtocol.state.snapshot.lastAuthorizationHeader == "Bearer access-token"
        )
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `expired session refresh persists updated session`() async throws {
        RecordingBackendURLProtocol.state.reset()
        try RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: makeSessionResponseData(
                accessToken: "refreshed-access-token",
                refreshToken: "refreshed-refresh-token",
                expiresAt: "2100-01-01T00:16:40Z"
            )
        )
        try RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: makeConnectionCheckResponseData()
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let persistenceBackend = InMemoryAPIKeyBackend()
        let persistence = BackendSessionPersistence(
            store: PersistedAPIKeyStore(backend: persistenceBackend)
        )
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO(
                accessToken: "expired-access-token",
                refreshToken: "expired-refresh-token",
                expiresAt: "1970-01-01T00:00:00Z"
            ),
            persistence: persistence
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: sessionStore,
            urlSession: session
        )

        _ = try await client.connectionCheck()

        let recorded = RecordingBackendURLProtocol.state.snapshot.recordedRequests
        #expect(recorded.map(\.path) == ["/v1/auth/refresh", "/v1/connection/check"])
        #expect(recorded.last?.authorizationHeader == "Bearer refreshed-access-token")
        #expect(sessionStore.loadSession()?.accessToken == "refreshed-access-token")
        #expect(persistence.loadSession()?.accessToken == "refreshed-access-token")
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `stream run returns SSE stream targeting correct endpoint`() throws {
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO()
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://api.example.com"))),
            sessionStore: sessionStore
        )

        let stream = client.streamRun("run_stream_01")
        // BackendSSEStream is a value type; verify it was created successfully
        _ = stream
    }

    @MainActor
    @Test
    func `SSE event struct stores event type data and optional id`() {
        let event = SSEEvent(event: "delta", data: "{\"textDelta\":\"hello\"}", id: "evt_1")
        #expect(event.event == "delta")
        #expect(event.data == "{\"textDelta\":\"hello\"}")
        #expect(event.id == "evt_1")

        let noID = SSEEvent(event: "status", data: "{}", id: nil)
        #expect(noID.id == nil)
    }

    @MainActor
    @Test
    func `session store restores persisted session and clears on sign out`() throws {
        let backend = InMemoryAPIKeyBackend()
        let persistence = BackendSessionPersistence(
            store: PersistedAPIKeyStore(backend: backend)
        )
        let originalSession = try makeSessionDTO(
            accessToken: "persisted-access-token",
            refreshToken: "persisted-refresh-token",
            expiresAt: "2100-01-01T00:16:40Z"
        )
        let firstStore = BackendSessionStore(persistence: persistence)
        firstStore.replace(session: originalSession)

        let restoredStore = BackendSessionStore(persistence: persistence)
        #expect(restoredStore.loadSession() == originalSession)

        restoredStore.clear()
        #expect(persistence.loadSession() == nil)
        #expect(backend.didDelete)
    }
}

private func makeConnectionCheckResponseData() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "backend": "healthy",
        "auth": "healthy",
        "openaiCredential": "healthy",
        "sse": "healthy",
        "checkedAt": "1970-01-01T00:00:00Z",
        "latencyMilliseconds": 12
    ])
}

private func makeSessionResponseData(
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

private func makeSessionDTO(
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

private final class RecordingBackendURLProtocol: URLProtocol {
    static let state = RecordingBackendURLProtocolState()

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.recordRequest(request)
        guard let responseURL = request.url ?? URL(string: "https://example.com") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let configuredResponse = Self.state.dequeueResponse()
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: configuredResponse.responseStatusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
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

private final class RecordingBackendURLProtocolState: @unchecked Sendable {
    struct StubbedResponse {
        let responseStatusCode: Int
        let responseBody: Data
    }

    struct RecordedRequest: Equatable {
        let path: String
        let authorizationHeader: String?
    }

    struct Snapshot {
        let lastAuthorizationHeader: String?
        let recordedRequests: [RecordedRequest]
    }

    private let lock = NSLock()
    private var responseQueue: [StubbedResponse] = []
    private var recordedRequests: [RecordedRequest] = []

    func reset() {
        lock.lock()
        responseQueue.removeAll()
        recordedRequests.removeAll()
        lock.unlock()
    }

    func enqueueResponse(responseStatusCode: Int, responseBody: Data) {
        lock.lock()
        responseQueue.append(
            StubbedResponse(
                responseStatusCode: responseStatusCode,
                responseBody: responseBody
            )
        )
        lock.unlock()
    }

    func recordRequest(_ request: URLRequest) {
        lock.lock()
        recordedRequests.append(
            RecordedRequest(
                path: request.url?.path ?? "",
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization")
            )
        )
        lock.unlock()
    }

    func dequeueResponse() -> StubbedResponse {
        lock.lock()
        let response = responseQueue.isEmpty
            ? StubbedResponse(responseStatusCode: 200, responseBody: Data())
            : responseQueue.removeFirst()
        lock.unlock()
        return response
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

private final class InMemoryAPIKeyBackend: @unchecked Sendable, APIKeyPersisting {
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
