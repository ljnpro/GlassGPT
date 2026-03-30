import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatPresentation
import Foundation
import GeneratedFilesCache
import Testing

@Suite(.tags(.presentation))
@MainActor
struct ChatPresentationCoverageTests {
    @Test func `settings account store derives degraded and unavailable sync states`() async {
        let sessionStore = BackendSessionStore(session: TestFixtures.session())
        let client = PresentationBackendRequester()
        let store = SettingsAccountStore(sessionStore: sessionStore, client: client)

        client.connectionCheckResult = .success(
            ConnectionCheckDTO(
                backend: .degraded,
                auth: .healthy,
                openaiCredential: .healthy,
                sse: .healthy,
                checkedAt: .now,
                latencyMilliseconds: 12,
                errorSummary: nil
            )
        )
        await store.checkConnection()
        #expect(store.syncStatusState == .degraded)
        #expect(store.syncStatusText == "Available with Degraded Realtime")

        client.connectionCheckResult = .success(
            ConnectionCheckDTO(
                backend: .unavailable,
                auth: .healthy,
                openaiCredential: .healthy,
                sse: .healthy,
                checkedAt: .now,
                latencyMilliseconds: nil,
                errorSummary: nil
            )
        )
        await store.checkConnection()
        #expect(store.syncStatusState == .unavailable)
        #expect(store.syncStatusText == "Backend Unavailable")

        client.connectionCheckResult = .failure(PresentationTestError.network)
        await store.checkConnection()
        #expect(store.connectionStatus == nil)
        #expect(store.syncStatusState == .unavailable)
        #expect(store.syncStatusText == "Connection Check Failed")
        #expect(store.lastErrorMessage == PresentationTestError.network.localizedDescription)
    }

    @Test func `settings account store delegates sign in and sign out actions`() async {
        let sessionStore = BackendSessionStore()
        let client = PresentationBackendRequester()
        let store = SettingsAccountStore(
            sessionStore: sessionStore,
            client: client,
            signInAction: {
                sessionStore.replace(session: TestFixtures.session(displayName: nil, email: nil))
            },
            signOutAction: {
                sessionStore.clear()
            }
        )

        #expect(store.displayName == "Not Signed In")
        #expect(store.subtitle == "Sign in with Apple to enable sync.")

        await store.signIn()
        #expect(store.isSignedIn)
        #expect(store.displayName == "Not Signed In")
        #expect(store.subtitle == "apple-user")

        client.connectionCheckResult = .success(
            ConnectionCheckDTO(
                backend: .healthy,
                auth: .healthy,
                openaiCredential: .healthy,
                sse: .unauthorized,
                checkedAt: .now,
                latencyMilliseconds: nil,
                errorSummary: nil
            )
        )
        await store.signOut()
        #expect(!store.isSignedIn)
        #expect(store.connectionStatus == nil)
    }

    @Test func `settings credentials store refreshes saves and deletes credential state`() async {
        let sessionStore = BackendSessionStore(session: TestFixtures.session())
        let client = PresentationBackendRequester()
        let store = SettingsCredentialsStore(client: client, sessionStore: sessionStore)

        #expect(store.isSignedIn)
        #expect(store.statusLabel == "Status unknown. Use Check Connection to refresh.")

        client.connectionCheckResult = .success(
            ConnectionCheckDTO(
                backend: .healthy,
                auth: .healthy,
                openaiCredential: .invalid,
                sse: .healthy,
                checkedAt: .init(timeIntervalSince1970: 55),
                latencyMilliseconds: nil,
                errorSummary: "bad key"
            )
        )
        await store.refreshStatus()
        #expect(store.credentialStatus?.state == .invalid)
        #expect(store.statusLabel == "bad key")

        store.apiKey = "  sk-test-value  "
        client.storeOpenAIKeyResult = .success(
            CredentialStatusDTO(
                provider: "openai",
                state: .valid,
                checkedAt: .init(timeIntervalSince1970: 66),
                lastErrorSummary: nil
            )
        )
        await store.saveAPIKey()
        #expect(store.apiKey.isEmpty)
        #expect(store.saveConfirmation)
        #expect(store.credentialStatus?.state == .valid)
        #expect(store.statusLabel == "Your OpenAI API key is stored and valid.")
        #expect(client.storedAPIKeys == ["sk-test-value"])

        await store.deleteAPIKey()
        #expect(store.credentialStatus?.state == .missing)
        #expect(store.statusLabel == "No OpenAI API key is stored on the backend.")
        #expect(client.deleteOpenAIKeyCallCount == 1)
    }

    @Test func `settings credentials store handles signed out and error states`() async {
        let signedOut = SettingsCredentialsStore(
            client: PresentationBackendRequester(),
            sessionStore: BackendSessionStore()
        )

        #expect(!signedOut.isSignedIn)
        #expect(signedOut.statusLabel == "Sign in to manage your OpenAI API key.")

        await signedOut.refreshStatus()
        #expect(signedOut.credentialStatus == nil)
        #expect(signedOut.lastErrorMessage == nil)

        let sessionStore = BackendSessionStore(session: TestFixtures.session())
        let client = PresentationBackendRequester()
        client.connectionCheckResult = .failure(PresentationTestError.network)
        let signedIn = SettingsCredentialsStore(client: client, sessionStore: sessionStore)

        await signedIn.refreshStatus()
        #expect(signedIn.lastErrorMessage == PresentationTestError.network.localizedDescription)

        signedIn.apiKey = "sk-error"
        client.storeOpenAIKeyResult = .failure(PresentationTestError.network)
        await signedIn.saveAPIKey()
        #expect(signedIn.lastErrorMessage == PresentationTestError.network.localizedDescription)

        client.deleteOpenAIKeyResult = .failure(PresentationTestError.network)
        await signedIn.deleteAPIKey()
        #expect(signedIn.lastErrorMessage == PresentationTestError.network.localizedDescription)
    }

    @Test func `history presenter filters refreshes and routes selection`() {
        var summaries = [
            HistoryConversationSummary(
                id: "c1",
                mode: .chat,
                title: "Release Notes",
                preview: "latest preview",
                updatedAt: .init(timeIntervalSince1970: 1),
                modelDisplayName: "GPT-5.4"
            ),
            HistoryConversationSummary(
                id: "c2",
                mode: .agent,
                title: "Roadmap",
                preview: "worker output",
                updatedAt: .init(timeIntervalSince1970: 2),
                modelDisplayName: "o3"
            )
        ]
        var selectedConversation: (String, ConversationMode)?
        var openSettingsCount = 0
        let presenter = HistoryPresenter(
            conversations: summaries,
            loadConversations: { summaries },
            selectConversation: { selectedConversation = ($0, $1) },
            isSignedIn: { true },
            openSettings: { openSettingsCount += 1 }
        )

        #expect(presenter.filteredConversations.count == 2)
        presenter.searchText = "release"
        #expect(presenter.filteredConversations.map(\.id) == ["c1"])

        presenter.selectConversation(id: "c1")
        #expect(selectedConversation?.0 == "c1")
        #expect(selectedConversation?.1 == .chat)

        presenter.selectConversation(id: "missing")
        #expect(selectedConversation?.0 == "c1")

        summaries = [
            HistoryConversationSummary(
                id: "c3",
                mode: .agent,
                title: "Postmortem",
                preview: "new preview",
                updatedAt: .init(timeIntervalSince1970: 3),
                modelDisplayName: "GPT-5.4"
            )
        ]
        presenter.searchText = ""
        presenter.refresh()
        #expect(presenter.filteredConversations.map(\.id) == ["c3"])

        presenter.openSettings()
        #expect(openSettingsCount == 1)
        #expect(presenter.isSignedIn)
    }

    @Test func `settings cache store refreshes and clears both cache buckets`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheManager = GeneratedFileCacheManager(cacheRootOverride: root)
        let store = SettingsCacheStore(
            generatedImageCacheLimitString: "250 MB",
            generatedDocumentCacheLimitString: "250 MB",
            cacheManager: cacheManager
        )

        let imageStore = GeneratedFileCacheStore(cacheRootOverride: root)
        _ = try imageStore.storeGeneratedFile(
            data: Data(repeating: 0x01, count: 12),
            filename: "preview.png",
            cacheKey: "image-1",
            bucket: .image
        )
        _ = try imageStore.storeGeneratedFile(
            data: Data(repeating: 0x02, count: 24),
            filename: "report.pdf",
            cacheKey: "doc-1",
            bucket: .document
        )

        await store.refreshAll()
        #expect(store.generatedImageCacheSizeBytes == 12)
        #expect(store.generatedDocumentCacheSizeBytes == 24)
        #expect(!store.generatedImageCacheSizeString.isEmpty)
        #expect(!store.generatedDocumentCacheSizeString.isEmpty)

        await store.clearGeneratedImageCache()
        #expect(store.generatedImageCacheSizeBytes == 0)
        #expect(!store.isClearingImageCache)

        await store.clearGeneratedDocumentCache()
        #expect(store.generatedDocumentCacheSizeBytes == 0)
        #expect(!store.isClearingDocumentCache)
    }
}

@MainActor
final class PresentationBackendRequester: BackendRequesting {
    var connectionCheckResult: Result<ConnectionCheckDTO, Error> = .success(
        ConnectionCheckDTO(
            backend: .healthy,
            auth: .healthy,
            openaiCredential: .healthy,
            sse: .healthy,
            checkedAt: .now,
            latencyMilliseconds: 1,
            errorSummary: nil
        )
    )
    var storeOpenAIKeyResult: Result<CredentialStatusDTO, Error> = .success(
        CredentialStatusDTO(provider: "openai", state: .valid, checkedAt: .now, lastErrorSummary: nil)
    )
    var deleteOpenAIKeyResult: Result<Void, Error> = .success(())
    var storedAPIKeys: [String] = []
    var deleteOpenAIKeyCallCount = 0

    func cancelRun(_: String) async throws -> RunSummaryDTO {
        throw PresentationTestError.unimplemented
    }

    func createConversation(
        title _: String,
        mode _: ConversationModeDTO,
        model _: ModelDTO?,
        reasoningEffort _: ReasoningEffortDTO?,
        agentWorkerReasoningEffort _: ReasoningEffortDTO?,
        serviceTier _: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        throw PresentationTestError.unimplemented
    }

    func fetchConversationDetail(_: String) async throws -> ConversationDetailDTO {
        throw PresentationTestError.unimplemented
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        throw PresentationTestError.unimplemented
    }

    func fetchCurrentUser() async throws -> UserDTO {
        throw PresentationTestError.unimplemented
    }

    func fetchRun(_: String) async throws -> RunSummaryDTO {
        throw PresentationTestError.unimplemented
    }

    func authenticateWithApple(_: AppleSignInPayload, deviceID _: String) async throws -> SessionDTO {
        throw PresentationTestError.unimplemented
    }

    func refreshSession() async throws -> SessionDTO {
        throw PresentationTestError.unimplemented
    }

    func retryRun(_: String) async throws -> RunSummaryDTO {
        throw PresentationTestError.unimplemented
    }

    func sendMessage(_: String, to _: String, imageBase64 _: String?, fileIds _: [String]?) async throws -> RunSummaryDTO {
        throw PresentationTestError.unimplemented
    }

    func startAgentRun(prompt _: String?, in _: String) async throws -> RunSummaryDTO {
        throw PresentationTestError.unimplemented
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
        throw PresentationTestError.unimplemented
    }

    func updateConversationConfiguration(
        _: String,
        model _: ModelDTO?,
        reasoningEffort _: ReasoningEffortDTO?,
        agentWorkerReasoningEffort _: ReasoningEffortDTO?,
        serviceTier _: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        throw PresentationTestError.unimplemented
    }

    func logout() async throws {}

    func storeOpenAIKey(_ apiKey: String) async throws -> CredentialStatusDTO {
        storedAPIKeys.append(apiKey)
        return try storeOpenAIKeyResult.get()
    }

    func deleteOpenAIKey() async throws {
        deleteOpenAIKeyCallCount += 1
        _ = try deleteOpenAIKeyResult.get()
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        try connectionCheckResult.get()
    }
}

enum PresentationTestError: LocalizedError {
    case network
    case unimplemented

    var errorDescription: String? {
        switch self {
        case .network:
            "network failed"
        case .unimplemented:
            "unimplemented"
        }
    }
}
