import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import GeneratedFilesCache
import GeneratedFilesCore
import NativeChatBackendCore
import SwiftData

@MainActor
struct SnapshotHarness {
    let client: SnapshotBackendRequester
    let sessionStore: BackendSessionStore
    let settingsStore: SettingsStore
    let loader: BackendConversationLoader
    let settingsPresenter: SettingsPresenter
    let cacheRoot: URL

    func makeShellState(selectedTab: Int = 3) -> NativeChatShellState {
        NativeChatShellState(
            chatController: makeChatController(),
            agentController: makeAgentController(),
            settingsPresenter: settingsPresenter,
            historyPresenter: makeSnapshotHistoryPresenter(),
            selectedTab: selectedTab
        )
    }

    func makeChatController() -> BackendChatController {
        let controller = BackendChatController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
        controller.skipAutomaticBootstrap = true
        return controller
    }

    func makeAgentController() -> BackendAgentController {
        let controller = BackendAgentController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
        controller.skipAutomaticBootstrap = true
        return controller
    }
}

@MainActor
func makeSnapshotHarness(signedIn: Bool) throws -> SnapshotHarness {
    let client = SnapshotBackendRequester()
    let sessionStore = BackendSessionStore(session: signedIn ? makeSnapshotSession() : nil)
    let settingsStore = SettingsStore()
    let schema = Schema([Conversation.self, Message.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let projectionStore = BackendProjectionStore(
        cacheRepository: ProjectionCacheRepository(modelContext: ModelContext(container)),
        cursorStore: SyncCursorStore()
    )
    let loader = BackendConversationLoader(
        client: client,
        projectionStore: projectionStore,
        sessionStore: sessionStore
    )
    let cacheRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheManager = GeneratedFileCacheManager(cacheRootOverride: cacheRoot)
    let presenter = SettingsPresenter(
        account: SettingsAccountStore(sessionStore: sessionStore, client: client),
        credentials: SettingsCredentialsStore(client: client, sessionStore: sessionStore),
        defaults: SettingsDefaultsStore(settingsStore: settingsStore),
        agentDefaults: AgentSettingsDefaultsStore(settingsStore: settingsStore),
        cache: SettingsCacheStore(
            generatedImageCacheLimitString: "250 MB",
            generatedDocumentCacheLimitString: "250 MB",
            cacheManager: cacheManager
        ),
        about: SettingsAboutInfo(appVersionString: "5.5.0 (20224)", platformString: "iOS 26.4")
    )

    return SnapshotHarness(
        client: client,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        loader: loader,
        settingsPresenter: presenter,
        cacheRoot: cacheRoot
    )
}

@MainActor
func makeSnapshotHistoryPresenter() -> HistoryPresenter {
    HistoryPresenter(
        conversations: [
            HistoryConversationSummary(
                id: "conv_chat",
                mode: .chat,
                title: "5.5.0 Release Plan",
                preview: "Close the remaining release gates before publishing.",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                modelDisplayName: "GPT-5.4 Pro"
            ),
            HistoryConversationSummary(
                id: "conv_agent",
                mode: .agent,
                title: "Launch Audit",
                preview: "Workers finished the rollout review.",
                updatedAt: Date(timeIntervalSince1970: 1_699_994_600),
                modelDisplayName: "Leader High / Worker Medium"
            )
        ],
        loadConversations: { [] },
        selectConversation: { _, _ in },
        isSignedIn: { true },
        openSettings: {}
    )
}

func makeSnapshotSession() -> SessionDTO {
    SessionDTO(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: .now.addingTimeInterval(3600),
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

func makeSnapshotMessageSurface(
    role: MessageRole = .assistant,
    content: String = "Rendered message",
    isComplete: Bool = true,
    includeTrace: Bool = false
) -> BackendMessageSurface {
    let message = Message(
        role: role,
        content: content,
        thinking: role == .assistant ? "Reasoning" : nil,
        isComplete: isComplete,
        annotations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
        toolCalls: [ToolCallInfo(id: "tool_1", type: .codeInterpreter, status: .completed, code: "print(1)", results: ["1"])],
        fileAttachments: [FileAttachment(filename: "report.pdf", fileSize: 12, fileType: "pdf", fileId: "file_1", uploadStatus: .uploaded)],
        filePathAnnotations: [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "/tmp/report.pdf",
                filename: "report.pdf",
                startIndex: 0,
                endIndex: 4
            )
        ],
        agentTrace: includeTrace ? makeCompletedAgentTrace() : nil
    )
    return BackendMessageSurface(message: message)
}

private func makeCompletedAgentTrace() -> AgentTurnTrace {
    AgentTurnTrace(
        leaderBriefSummary: "Prefer the lowest-risk rollout path.",
        workerSummaries: [
            AgentWorkerSummary(role: .workerA, summary: "Keep parity checks visible."),
            AgentWorkerSummary(role: .workerB, summary: "Use staged promotion and rollback gates.")
        ],
        processSnapshot: AgentProcessSnapshot(
            activity: .completed,
            currentFocus: "Release complete",
            leaderAcceptedFocus: "Release complete",
            leaderLiveStatus: "Completed",
            leaderLiveSummary: "All release gates are green.",
            outcome: "Completed"
        ),
        completedStage: .finalSynthesis,
        outcome: "Completed"
    )
}

@MainActor
final class SnapshotBackendRequester: BackendRequesting {
    var conversations: [ConversationDTO] = []
    var detail: ConversationDetailDTO?
    var connectionStatus = ConnectionCheckDTO(
        backend: .healthy,
        auth: .healthy,
        openaiCredential: .healthy,
        sse: .healthy,
        checkedAt: .now,
        latencyMilliseconds: 12,
        errorSummary: nil
    )

    func cancelRun(_ runID: String) async throws -> RunSummaryDTO {
        makeRunSummary(id: runID)
    }

    func fetchConversationDetail(_ conversationID: String) async throws -> ConversationDetailDTO {
        detail
            ?? ConversationDetailDTO(
                conversation: ConversationDTO(
                    id: conversationID,
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
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        conversations
    }

    func fetchCurrentUser() async throws -> UserDTO {
        makeSnapshotSession().user
    }

    func fetchRun(_ runID: String) async throws -> RunSummaryDTO {
        makeRunSummary(id: runID)
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        connectionStatus
    }

    func authenticateWithApple(_ payload: AppleSignInPayload, deviceID: String) async throws -> SessionDTO {
        _ = payload
        var session = makeSnapshotSession()
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
        makeSnapshotSession()
    }

    func retryRun(_ runID: String) async throws -> RunSummaryDTO {
        makeRunSummary(id: runID)
    }

    func sendMessage(
        _ content: String,
        to conversationID: String,
        imageBase64 _: String?,
        fileIds _: [String]?
    ) async throws -> RunSummaryDTO {
        _ = content
        return makeRunSummary(id: "run_\(conversationID)")
    }

    func startAgentRun(prompt: String?, in conversationID: String) async throws -> RunSummaryDTO {
        _ = prompt
        return makeRunSummary(id: "run_\(conversationID)")
    }

    func streamRun(_ runID: String, lastEventID: String?) async throws -> BackendSSEStream {
        _ = runID
        _ = lastEventID
        return BackendSSEStream(testEvents: [])
    }

    func syncEvents(after cursor: String?) async throws -> SyncEnvelopeDTO {
        _ = cursor
        return SyncEnvelopeDTO(nextCursor: nil, events: [])
    }

    func logout() async throws {}
    func storeOpenAIKey(_ apiKey: String) async throws -> CredentialStatusDTO {
        _ = apiKey
        return CredentialStatusDTO(provider: "openai", state: .valid, checkedAt: .now, lastErrorSummary: nil)
    }

    func deleteOpenAIKey() async throws {}

    func createConversation(
        title: String,
        mode: ConversationModeDTO,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        let dto = ConversationDTO(
            id: "conv_\(mode.rawValue)",
            title: title,
            mode: mode,
            createdAt: .now,
            updatedAt: .now,
            lastRunID: nil,
            lastSyncCursor: nil,
            model: model,
            reasoningEffort: reasoningEffort,
            agentWorkerReasoningEffort: agentWorkerReasoningEffort,
            serviceTier: serviceTier
        )
        conversations = [dto]
        return dto
    }

    func updateConversationConfiguration(
        _ conversationID: String,
        model: ModelDTO?,
        reasoningEffort: ReasoningEffortDTO?,
        agentWorkerReasoningEffort: ReasoningEffortDTO?,
        serviceTier: ServiceTierDTO?
    ) async throws -> ConversationDTO {
        let existingMode = conversations.first?.mode ?? .chat
        let updated = ConversationDTO(
            id: conversationID,
            title: conversations.first?.title ?? "Conversation",
            mode: existingMode,
            createdAt: conversations.first?.createdAt ?? .now,
            updatedAt: .now,
            lastRunID: conversations.first?.lastRunID,
            lastSyncCursor: conversations.first?.lastSyncCursor,
            model: model,
            reasoningEffort: reasoningEffort,
            agentWorkerReasoningEffort: agentWorkerReasoningEffort,
            serviceTier: serviceTier
        )
        conversations = [updated]
        return updated
    }

    private func makeRunSummary(id: String) -> RunSummaryDTO {
        RunSummaryDTO(
            id: id,
            conversationID: "conv_1",
            kind: .chat,
            status: .completed,
            stage: .finalSynthesis,
            createdAt: .now,
            updatedAt: .now,
            lastEventCursor: nil,
            visibleSummary: "Done",
            processSnapshotJSON: nil
        )
    }
}
