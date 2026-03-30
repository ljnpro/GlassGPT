import BackendAuth
import BackendClient
import BackendContracts
import ChatPersistenceCore
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import SwiftData
import Testing

struct LoaderHarness {
    let defaultsSuiteName: String
    let loader: BackendConversationLoader
    let projectionStore: BackendProjectionStore
}

@MainActor
func makeLoaderHarness(client: LoaderBackendRequester) throws -> LoaderHarness {
    let schema = Schema([Conversation.self, Message.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let defaultsSuiteName = "BackendConversationLoaderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
    let projectionStore = BackendProjectionStore(
        cacheRepository: ProjectionCacheRepository(modelContext: ModelContext(container)),
        cursorStore: SyncCursorStore(valueStore: UserDefaultsSettingsValueStore(defaults: defaults))
    )
    let loader = BackendConversationLoader(
        client: client,
        projectionStore: projectionStore,
        sessionStore: BackendSessionStore(session: makeLoaderSession())
    )
    return LoaderHarness(
        defaultsSuiteName: defaultsSuiteName,
        loader: loader,
        projectionStore: projectionStore
    )
}

func makeLoaderSession() -> SessionDTO {
    SessionDTO(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: .init(timeIntervalSince1970: 3600),
        deviceID: "device_1",
        user: UserDTO(
            id: "user_1",
            appleSubject: "apple-user",
            displayName: "Taylor",
            email: "taylor@example.com",
            createdAt: .init(timeIntervalSince1970: 1)
        )
    )
}

struct CreateConversationCall: Equatable {
    let title: String
    let mode: ConversationModeDTO
    let model: ModelDTO?
    let reasoningEffort: ReasoningEffortDTO?
    let agentWorkerReasoningEffort: ReasoningEffortDTO?
    let serviceTier: ServiceTierDTO?
}

struct UpdateConversationConfigurationCall: Equatable {
    let conversationID: String
    let model: ModelDTO?
    let reasoningEffort: ReasoningEffortDTO?
    let agentWorkerReasoningEffort: ReasoningEffortDTO?
    let serviceTier: ServiceTierDTO?
}

@MainActor
final class LoaderBackendRequester: BackendRequesting {
    var createConversationCalls: [CreateConversationCall] = []
    var updateConversationConfigurationCalls: [UpdateConversationConfigurationCall] = []
    var createConversationResponse = ConversationDTO(
        id: "conv_default",
        title: "Conversation",
        mode: .chat,
        createdAt: .now,
        updatedAt: .now,
        lastRunID: nil,
        lastSyncCursor: nil
    )
    var detailResponse = ConversationDetailDTO(
        conversation: ConversationDTO(
            id: "conv_default",
            title: "Conversation",
            mode: .chat,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: nil,
            lastSyncCursor: nil
        ),
        messages: [],
        runs: []
    )
    var updateConversationResponse = ConversationDTO(
        id: "conv_default",
        title: "Conversation",
        mode: .chat,
        createdAt: .now,
        updatedAt: .now,
        lastRunID: nil,
        lastSyncCursor: nil
    )

    func createConversation(
        title: String,
        mode: ConversationModeDTO,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        createConversationCalls.append(
            CreateConversationCall(
                title: title,
                mode: mode,
                model: model,
                reasoningEffort: reasoningEffort,
                agentWorkerReasoningEffort: agentWorkerReasoningEffort,
                serviceTier: serviceTier
            )
        )
        return createConversationResponse
    }

    func fetchConversationDetail(_ conversationID: String) async throws -> ConversationDetailDTO {
        #expect(detailResponse.conversation.id == conversationID)
        return detailResponse
    }

    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        updateConversationConfigurationCalls.append(
            UpdateConversationConfigurationCall(
                conversationID: conversationID,
                model: model,
                reasoningEffort: reasoningEffort,
                agentWorkerReasoningEffort: agentWorkerReasoningEffort,
                serviceTier: serviceTier
            )
        )
        return updateConversationResponse
    }

    func cancelRun(_: String) async throws -> RunSummaryDTO {
        throw URLError(.unsupportedURL)
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        []
    }

    func fetchCurrentUser() async throws -> UserDTO {
        makeLoaderSession().user
    }

    func fetchRun(_: String) async throws -> RunSummaryDTO {
        throw URLError(.unsupportedURL)
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        throw URLError(.unsupportedURL)
    }

    func authenticateWithApple(_: AppleSignInPayload, deviceID: String) async throws -> SessionDTO {
        var session = makeLoaderSession()
        session = SessionDTO(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt,
            deviceID: deviceID,
            user: session.user
        )
        return session
    }

    func refreshSession() async throws -> SessionDTO {
        makeLoaderSession()
    }

    func retryRun(_: String) async throws -> RunSummaryDTO {
        throw URLError(.unsupportedURL)
    }

    func sendMessage(_ content: String, to conversationID: String, imageBase64: String?, fileIds: [String]?) async throws -> RunSummaryDTO {
        throw URLError(.unsupportedURL)
    }

    func startAgentRun(prompt _: String?, in _: String) async throws -> RunSummaryDTO {
        throw URLError(.unsupportedURL)
    }

    func streamRun(_: String, lastEventID _: String?) async throws -> BackendSSEStream {
        BackendSSEStream(testEvents: [])
    }

    func syncEvents(after _: String?) async throws -> SyncEnvelopeDTO {
        SyncEnvelopeDTO(nextCursor: nil, events: [])
    }

    func logout() async throws {}

    func storeOpenAIKey(_: String) async throws -> CredentialStatusDTO {
        throw URLError(.unsupportedURL)
    }

    func deleteOpenAIKey() async throws {}
}
