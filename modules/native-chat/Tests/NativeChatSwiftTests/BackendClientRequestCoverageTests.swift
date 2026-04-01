import BackendAuth
import BackendContracts
import BackendSessionPersistence
import ChatPersistenceCore
import Foundation
import Testing
@testable import BackendClient

struct BackendClientRequestCoverageTests {
    @MainActor
    @Test
    func `request wrappers hit expected endpoints and payloads`() async throws {
        CoverageBackendURLProtocol.state.reset()
        try enqueueWrapperResponses()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverageBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = try BackendSessionStore(session: makeCoverageSessionDTO())
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: sessionStore,
            urlSession: session
        )

        _ = try await client.fetchCurrentUser()
        _ = try await client.fetchConversations()
        _ = try await client.fetchConversationDetail("conv_1")
        _ = try await client.createConversation(title: "Backend Chat", mode: .agent)
        _ = try await client.fetchRun("run_1")
        _ = try await client.cancelRun("run_1")
        _ = try await client.retryRun("run_1")
        _ = try await client.sendMessage(
            "Hello",
            to: "conv_1",
            imageBase64: "ZmFrZS1qcGVn",
            fileIds: ["file_1", "file_2"]
        )
        _ = try await client.startAgentRun(prompt: "Investigate", in: "conv_1")
        _ = try await client.syncEvents(after: "cur_0")
        _ = try await client.authenticateWithApple(
            AppleSignInPayload(
                userIdentifier: "apple-user",
                identityToken: "identity-token",
                authorizationCode: "authorization-code",
                email: "apple@example.com",
                givenName: "Glass",
                familyName: "User"
            ),
            deviceID: "device_1"
        )
        _ = try await client.refreshSession()
        let downloadedFile = try await client.downloadGeneratedFile(
            fileId: "file_1",
            containerId: "container_1"
        )
        _ = try await client.storeOpenAIKey("sk-test")
        try await client.deleteOpenAIKey()
        try await client.logout()

        let requests = CoverageBackendURLProtocol.state.snapshot.recordedRequests
        #expect(requests.map(\.path) == [
            "/v1/me",
            "/v1/conversations",
            "/v1/conversations/conv_1",
            "/v1/conversations",
            "/v1/runs/run_1",
            "/v1/runs/run_1/cancel",
            "/v1/runs/run_1/retry",
            "/v1/conversations/conv_1/messages",
            "/v1/conversations/conv_1/agent-runs",
            "/v1/sync/events",
            "/v1/auth/apple",
            "/v1/auth/refresh",
            "/v1/files/file_1/content",
            "/v1/credentials/openai",
            "/v1/credentials/openai",
            "/v1/auth/logout"
        ])
        #expect(requests.map(\.method) == [
            "GET",
            "GET",
            "GET",
            "POST",
            "GET",
            "POST",
            "POST",
            "POST",
            "POST",
            "GET",
            "POST",
            "POST",
            "GET",
            "PUT",
            "DELETE",
            "POST"
        ])
        #expect(requests[0].authorizationHeader == "Bearer access-token")
        #expect(requests[10].authorizationHeader == nil)
        #expect(requests[11].authorizationHeader == nil)
        #expect(requests[12].query == "container_id=container_1")
        #expect(requests[12].authorizationHeader == "Bearer refreshed-access-token")
        #expect(requests[13].authorizationHeader == "Bearer refreshed-access-token")
        #expect(requests[15].authorizationHeader == "Bearer refreshed-access-token")
        #expect(requests.allSatisfy { ($0.requestIDHeader ?? "").isEmpty == false })
        #expect(requests[7].body?.contains("\"imageBase64\":\"ZmFrZS1qcGVn\"") == true)
        #expect(requests[7].body?.contains("\"fileIds\":[\"file_1\",\"file_2\"]") == true)
        #expect(downloadedFile.data == Data("downloaded-generated-file".utf8))
        #expect(sessionStore.loadSession() == nil)
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `upload file posts multipart form data to backend file proxy`() async throws {
        CoverageBackendURLProtocol.state.reset()
        try CoverageBackendURLProtocol.state.enqueueResponse(
            statusCode: 201,
            body: Data(#"{"fileId":"file_upload_1"}"#.utf8)
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverageBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = try BackendSessionStore(session: makeCoverageSessionDTO())
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: sessionStore,
            urlSession: session
        )

        let fileID = try await client.uploadFile(
            data: Data("hello".utf8),
            filename: "notes.txt",
            mimeType: "text/plain"
        )

        let requests = CoverageBackendURLProtocol.state.snapshot.recordedRequests
        #expect(fileID == "file_upload_1")
        #expect(requests.count == 1)
        #expect(requests[0].path == "/v1/files/upload")
        #expect((requests[0].requestIDHeader ?? "").isEmpty == false)
        #expect(requests[0].body?.contains("name=\"file\"; filename=\"notes.txt\"") == true)
        #expect(requests[0].body?.contains("Content-Type: text/plain") == true)
        #expect(requests[0].body?.contains("name=\"purpose\"") == true)
        #expect(requests[0].body?.contains("user_data") == true)
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `make request applies authorization modes and query items`() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverageBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let signedInStore = try BackendSessionStore(session: makeCoverageSessionDTO())
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: signedInStore,
            urlSession: session
        )

        let request = try client.makeRequest(
            path: "/v1/sync/events",
            method: "GET",
            body: String?.none,
            authorizationMode: .ifAvailable,
            queryItems: [URLQueryItem(name: "cursor", value: "cur_42")]
        )

        #expect(request.url?.absoluteString == "https://example.com/v1/sync/events?cursor=cur_42")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)

        let bodyRequest = try client.makeRequest(
            path: "/v1/credentials/openai",
            method: "PUT",
            body: OpenAICredentialRequestDTO(apiKey: "sk-inline"),
            authorizationMode: .required,
            queryItems: []
        )
        #expect(bodyRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(
            bodyRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }?
                .contains("\"apiKey\":\"sk-inline\"") == true
        )

        let unsignedClient = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: BackendSessionStore(),
            urlSession: session
        )
        #expect(
            throws: BackendAPIError.unauthorized,
            performing: {
                _ = try unsignedClient.makeRequest(
                    path: "/v1/me",
                    method: "GET",
                    body: String?.none,
                    authorizationMode: .required,
                    queryItems: []
                )
            }
        )
        session.invalidateAndCancel()
    }

    @MainActor
    @Test
    func `validate maps backend status codes and response bodies`() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverageBackendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = try BackendClient(
            environment: BackendEnvironment(baseURL: #require(URL(string: "https://example.com"))),
            sessionStore: BackendSessionStore(),
            urlSession: session
        )
        let responseURL = try #require(URL(string: "https://example.com"))

        func response(_ statusCode: Int) throws -> HTTPURLResponse {
            let response = HTTPURLResponse(
                url: responseURL,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: [:]
            )
            return try #require(response)
        }

        #expect(throws: BackendAPIError.invalidRequest) {
            _ = try client.validate(response: response(400), data: Data())
        }
        #expect(throws: BackendAPIError.unauthorized) {
            _ = try client.validate(response: response(401), data: Data())
        }
        #expect(throws: BackendAPIError.forbidden) {
            _ = try client.validate(response: response(403), data: Data())
        }
        #expect(throws: BackendAPIError.notFound) {
            _ = try client.validate(response: response(404), data: Data())
        }
        #expect(throws: BackendAPIError.conflict) {
            _ = try client.validate(response: response(409), data: Data())
        }
        #expect(throws: BackendAPIError.rateLimited) {
            _ = try client.validate(response: response(429), data: Data())
        }
        #expect(throws: BackendAPIError.serviceUnavailable) {
            _ = try client.validate(response: response(503), data: Data())
        }
        #expect(throws: BackendAPIError.networkFailure("gateway down")) {
            _ = try client.validate(
                response: response(418),
                data: Data("gateway down".utf8)
            )
        }
        session.invalidateAndCancel()
    }
}
