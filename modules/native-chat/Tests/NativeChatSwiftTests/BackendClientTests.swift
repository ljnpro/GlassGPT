import BackendAuth
import BackendContracts
import BackendSessionPersistence
import ChatPersistenceCore
import Foundation
import Testing
@testable import BackendClient

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

        let response = try await client.connectionCheck()

        #expect(
            RecordingBackendURLProtocol.state.snapshot.lastAuthorizationHeader == "Bearer access-token"
        )
        #expect(
            RecordingBackendURLProtocol.state.snapshot.recordedRequests.last?.appVersionHeader == "5.4.0"
        )
        #expect(response.backendVersion == "5.4.0")
        #expect(response.minimumSupportedAppVersion == "5.3.0")
        #expect(response.appCompatibility == .compatible)
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

        let response = try await client.connectionCheck()

        let recorded = RecordingBackendURLProtocol.state.snapshot.recordedRequests
        #expect(recorded.map(\.path) == ["/v1/auth/refresh", "/v1/connection/check"])
        #expect(recorded.last?.authorizationHeader == "Bearer refreshed-access-token")
        #expect(recorded.last?.appVersionHeader == "5.4.0")
        #expect(sessionStore.loadSession()?.accessToken == "refreshed-access-token")
        #expect(persistence.loadSession()?.accessToken == "refreshed-access-token")
        #expect(response.backendVersion == "5.4.0")
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `connection check retries service unavailable and succeeds`() async throws {
        RecordingBackendURLProtocol.state.reset()
        RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 503,
            responseBody: Data()
        )
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

        try await withDeterministicRetryPolicy {
            _ = try await client.connectionCheck()
        }

        #expect(RecordingBackendURLProtocol.state.snapshot.recordedRequests.count == 2)
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `connection check retries transient url session failures and succeeds`() async throws {
        RecordingBackendURLProtocol.state.reset()
        RecordingBackendURLProtocol.state.enqueueFailure(URLError(.networkConnectionLost))
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

        try await withDeterministicRetryPolicy {
            _ = try await client.connectionCheck()
        }

        #expect(RecordingBackendURLProtocol.state.snapshot.recordedRequests.count == 2)
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `fetch conversations follows paginated cursors until hasMore is false`() async throws {
        RecordingBackendURLProtocol.state.reset()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: encoder.encode(
                ConversationPageDTO(
                    items: [
                        ConversationDTO(
                            id: "conv_1",
                            title: "Conversation 1",
                            mode: .chat,
                            createdAt: .init(timeIntervalSince1970: 1),
                            updatedAt: .init(timeIntervalSince1970: 2),
                            lastRunID: nil,
                            lastSyncCursor: nil
                        )
                    ],
                    nextCursor: "cursor-page-2",
                    hasMore: true
                )
            )
        )
        try RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: encoder.encode(
                ConversationPageDTO(
                    items: [
                        ConversationDTO(
                            id: "conv_2",
                            title: "Conversation 2",
                            mode: .agent,
                            createdAt: .init(timeIntervalSince1970: 3),
                            updatedAt: .init(timeIntervalSince1970: 4),
                            lastRunID: nil,
                            lastSyncCursor: nil
                        )
                    ],
                    nextCursor: nil,
                    hasMore: false
                )
            )
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

        let conversations = try await client.fetchConversations()

        #expect(conversations.map(\.id) == ["conv_1", "conv_2"])
        #expect(
            RecordingBackendURLProtocol.state.snapshot.recordedRequests.map(\.query) == [
                nil,
                "cursor=cursor-page-2"
            ]
        )
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `session persistence clears corrupt stored payloads`() throws {
        let backend = InMemoryAPIKeyBackend()
        let store = PersistedAPIKeyStore(backend: backend)
        try store.saveAPIKey("{not valid json")

        let persistence = BackendSessionPersistence(store: store)

        #expect(persistence.loadSession() == nil)
        #expect(backend.didDelete)
    }
}
