import BackendAuth
import BackendContracts
import BackendSessionPersistence
import ChatPersistenceCore
import Foundation
import Testing
@testable import BackendClient

extension BackendClientTests {
    @MainActor
    @Test
    func `stream run returns SSE stream targeting correct endpoint`() async throws {
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO()
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://api.example.com"))),
            sessionStore: sessionStore
        )

        let stream = try await client.streamRun("run_stream_01")
        _ = stream
    }

    @MainActor
    @Test
    func `stream run refreshes expired session before opening SSE`() async throws {
        RecordingBackendURLProtocol.state.reset()
        try RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: makeSessionResponseData(
                accessToken: "refreshed-access-token",
                refreshToken: "refreshed-refresh-token",
                expiresAt: "2100-01-01T00:16:40Z"
            )
        )
        RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: Data(
                """
                id: stream_run_01_00000001
                event: delta
                data: {"textDelta":"hello"}

                """.utf8
            ),
            responseHeaders: ["Content-Type": "text/event-stream"]
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO(
                accessToken: "expired-access-token",
                refreshToken: "expired-refresh-token",
                expiresAt: "1970-01-01T00:00:00Z"
            )
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://api.example.com"))),
            sessionStore: sessionStore,
            urlSession: session,
            sseURLSession: session
        )

        let stream = try await client.streamRun("run_stream_refresh")
        var iterator = stream.makeAsyncIterator()
        let event = try await iterator.next()

        let recorded = RecordingBackendURLProtocol.state.snapshot.recordedRequests
        #expect(recorded.map(\.path) == ["/v1/auth/refresh", "/v1/runs/run_stream_refresh/stream"])
        #expect(recorded.last?.authorizationHeader == "Bearer refreshed-access-token")
        #expect(recorded.last?.appVersionHeader == "5.3.2")
        #expect(event?.event == "delta")
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `stream run surfaces non-success stream setup as an explicit SSE error`() async throws {
        RecordingBackendURLProtocol.state.reset()
        RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 401,
            responseBody: Data()
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO()
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://api.example.com"))),
            sessionStore: sessionStore,
            urlSession: session,
            sseURLSession: session
        )

        var iterator = try await client.streamRun("run_stream_401").makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected unacceptable status code stream failure")
        } catch let error as BackendSSEStreamError {
            #expect(error == .unacceptableStatusCode(401))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `stream run forwards last event id for SSE resume and parses event ids`() async throws {
        RecordingBackendURLProtocol.state.reset()
        RecordingBackendURLProtocol.state.enqueueResponse(
            responseStatusCode: 200,
            responseBody: Data(
                """
                id: cur_00000000000000000007
                event: delta
                data: {"textDelta":"hello"}

                """.utf8
            ),
            responseHeaders: ["Content-Type": "text/event-stream"]
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = try BackendSessionStore(
            session: makeSessionDTO()
        )
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://api.example.com"))),
            sessionStore: sessionStore,
            urlSession: session,
            sseURLSession: session
        )

        let stream = try await client.streamRun(
            "run_stream_resume",
            lastEventID: "cur_00000000000000000006"
        )
        var iterator = stream.makeAsyncIterator()
        let event = try await iterator.next()

        #expect(event?.event == "delta")
        #expect(event?.id == "cur_00000000000000000007")
        #expect(
            RecordingBackendURLProtocol.state.snapshot.recordedRequests.last?.lastEventIDHeader
                == "cur_00000000000000000006"
        )
        #expect(
            RecordingBackendURLProtocol.state.snapshot.recordedRequests.last?.appVersionHeader
                == "5.3.2"
        )
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `scripted SSE stream distinguishes connection setup transport failures`() async {
        var iterator = BackendSSEStream(
            testEvents: [],
            setupError: .transportFailure(.connectionSetup, .timedOut)
        ).makeAsyncIterator()

        do {
            _ = try await iterator.next()
            Issue.record("Expected connection setup transport failure")
        } catch let error as BackendSSEStreamError {
            #expect(error == .transportFailure(.connectionSetup, .timedOut))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test
    func `scripted SSE stream distinguishes mid-stream transport failures`() async throws {
        var iterator = BackendSSEStream(
            testEvents: [SSEEvent(event: "delta", data: "{\"textDelta\":\"hello\"}", id: nil)],
            nextError: .transportFailure(.streamRead, .networkConnectionLost)
        ).makeAsyncIterator()

        let firstEvent = try await iterator.next()
        #expect(firstEvent?.event == "delta")

        do {
            _ = try await iterator.next()
            Issue.record("Expected mid-stream transport failure")
        } catch let error as BackendSSEStreamError {
            #expect(error == .transportFailure(.streamRead, .networkConnectionLost))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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
