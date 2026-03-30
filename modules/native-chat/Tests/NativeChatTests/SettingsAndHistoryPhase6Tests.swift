import AppIntents
import BackendAuth
import BackendClient
import BackendContracts
import ChatPresentation
import Foundation
import XCTest

final class SettingsAndHistoryPhase6Tests: XCTestCase {
    @MainActor
    func testHistoryPresenterSupportsSignedOutSettingsCTA() {
        var openSettingsCount = 0
        let presenter = HistoryPresenter(
            loadConversations: { [] },
            selectConversation: { _, _ in },
            isSignedIn: { false },
            openSettings: { openSettingsCount += 1 }
        )

        XCTAssertFalse(presenter.isSignedIn)

        presenter.openSettings()

        XCTAssertEqual(openSettingsCount, 1)
    }

    @MainActor
    func testSettingsAccountStoreDerivesHealthySyncState() async throws {
        let sessionStore = try BackendSessionStore(session: makePhase6SessionDTO())
        let client = Phase6BackendRequester(
            connectionCheckResult: .success(
                ConnectionCheckDTO(
                    backend: .healthy,
                    auth: .healthy,
                    openaiCredential: .healthy,
                    sse: .healthy,
                    checkedAt: .init(timeIntervalSince1970: 100),
                    latencyMilliseconds: 42,
                    errorSummary: nil
                )
            )
        )
        let store = SettingsAccountStore(
            sessionStore: sessionStore,
            client: client
        )

        await store.checkConnection()

        XCTAssertEqual(store.sessionStatusState, .healthy)
        XCTAssertEqual(store.sessionStatusText, "Active")
        XCTAssertEqual(store.syncStatusState, .healthy)
        XCTAssertEqual(store.syncStatusText, "Realtime Sync Ready")
        XCTAssertEqual(store.connectionStatus?.latencyMilliseconds, 42)
        XCTAssertNotNil(store.lastCheckedText)
        XCTAssertNil(store.lastErrorMessage)
    }

    @MainActor
    func testSettingsAccountStoreReportsSignedOutState() {
        let store = SettingsAccountStore(
            sessionStore: BackendSessionStore(),
            client: Phase6BackendRequester(
                connectionCheckResult: .success(
                    ConnectionCheckDTO(
                        backend: .healthy,
                        auth: .healthy,
                        openaiCredential: .healthy,
                        sse: .healthy,
                        checkedAt: .init(timeIntervalSince1970: 100),
                        latencyMilliseconds: 1,
                        errorSummary: nil
                    )
                )
            )
        )

        XCTAssertEqual(store.sessionStatusState, .missing)
        XCTAssertEqual(store.sessionStatusText, "Sign In Required")
        XCTAssertEqual(store.syncStatusState, .missing)
        XCTAssertEqual(store.syncStatusText, "Not Available")
        XCTAssertNil(store.lastCheckedText)
    }
}

@MainActor
private final class Phase6BackendRequester: BackendRequesting {
    let connectionCheckResult: Result<ConnectionCheckDTO, Error>

    init(connectionCheckResult: Result<ConnectionCheckDTO, Error>) {
        self.connectionCheckResult = connectionCheckResult
    }

    func cancelRun(_: String) async throws -> RunSummaryDTO {
        throw Phase6TestError.unimplemented
    }

    func createConversation(
        title _: String,
        mode _: ConversationModeDTO,
        model _: ModelDTO?,
        reasoningEffort _: ReasoningEffortDTO?,
        agentWorkerReasoningEffort _: ReasoningEffortDTO?,
        serviceTier _: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        throw Phase6TestError.unimplemented
    }

    func fetchConversationDetail(_: String) async throws -> ConversationDetailDTO {
        throw Phase6TestError.unimplemented
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        throw Phase6TestError.unimplemented
    }

    func fetchCurrentUser() async throws -> UserDTO {
        throw Phase6TestError.unimplemented
    }

    func fetchRun(_: String) async throws -> RunSummaryDTO {
        throw Phase6TestError.unimplemented
    }

    func authenticateWithApple(
        _: AppleSignInPayload,
        deviceID _: String
    ) async throws -> SessionDTO {
        throw Phase6TestError.unimplemented
    }

    func refreshSession() async throws -> SessionDTO {
        throw Phase6TestError.unimplemented
    }

    func retryRun(_: String) async throws -> RunSummaryDTO {
        throw Phase6TestError.unimplemented
    }

    func sendMessage(_: String, to _: String, imageBase64 _: String?, fileIds _: [String]?) async throws -> RunSummaryDTO {
        throw Phase6TestError.unimplemented
    }

    func startAgentRun(prompt _: String?, in _: String) async throws -> RunSummaryDTO {
        throw Phase6TestError.unimplemented
    }

    func streamRun(_ runID: String, lastEventID _: String?) async throws -> BackendSSEStream {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "localhost"
        components.path = "/v1/runs/\(runID)/stream"
        let url = components.url ?? URL(fileURLWithPath: "/")
        return BackendSSEStream(url: url, urlSession: .shared, authorizationHeader: nil)
    }

    func syncEvents(after _: String?) async throws -> SyncEnvelopeDTO {
        throw Phase6TestError.unimplemented
    }

    func updateConversationConfiguration(
        _: String,
        model _: ModelDTO?,
        reasoningEffort _: ReasoningEffortDTO?,
        agentWorkerReasoningEffort _: ReasoningEffortDTO?,
        serviceTier _: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        throw Phase6TestError.unimplemented
    }

    func logout() async throws {}
    func storeOpenAIKey(_: String) async throws -> CredentialStatusDTO {
        throw Phase6TestError.unimplemented
    }

    func deleteOpenAIKey() async throws {}

    func connectionCheck() async throws -> ConnectionCheckDTO {
        try connectionCheckResult.get()
    }
}

private enum Phase6TestError: Error {
    case unimplemented
}

private func makePhase6SessionData() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "accessToken": "access-token",
        "refreshToken": "refresh-token",
        "expiresAt": "2100-01-01T00:16:40Z",
        "deviceId": "device_01",
        "user": [
            "id": "usr_phase6",
            "appleSubject": "apple-subject-phase6",
            "email": "phase6@example.com",
            "displayName": "Phase 6 User",
            "createdAt": "1970-01-01T00:00:00Z"
        ]
    ])
}

private func makePhase6SessionDTO() throws -> SessionDTO {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SessionDTO.self, from: makePhase6SessionData())
}
