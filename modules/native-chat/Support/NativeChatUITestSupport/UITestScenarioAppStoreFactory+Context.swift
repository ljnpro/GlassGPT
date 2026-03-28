import BackendAuth
import BackendContracts
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import GeneratedFilesCache
import NativeChatBackendCore
import SwiftData

struct ScenarioContext {
    let store: NativeChatShellState
    let chatController: BackendChatController
    let agentController: BackendAgentController
}

extension UITestScenarioAppStoreFactory {
    static func makeSession() -> SessionDTO {
        SessionDTO(
            accessToken: "uitest-access",
            refreshToken: "uitest-refresh",
            expiresAt: .now.addingTimeInterval(3600),
            deviceID: "uitest-device",
            user: UserDTO(
                id: "user_uitest",
                appleSubject: "apple-uitest",
                displayName: "UITest User",
                email: "uitest@example.com",
                createdAt: .now
            )
        )
    }

    static func makeScenarioContext(
        modelContext: ModelContext,
        selectedTab: Int
    ) -> ScenarioContext {
        let sessionStore = BackendSessionStore(session: makeSession())
        let client = UITestBackendRequester()
        let settingsStore = SettingsStore()
        let projectionStore = BackendProjectionStore(
            cacheRepository: ProjectionCacheRepository(modelContext: modelContext),
            cursorStore: SyncCursorStore()
        )
        let loader = BackendConversationLoader(
            client: client,
            projectionStore: projectionStore,
            sessionStore: sessionStore
        )
        let chatController = makeChatController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
        let agentController = makeAgentController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
        let settingsPresenter = makeSettingsPresenter(
            sessionStore: sessionStore,
            client: client,
            settingsStore: settingsStore
        )
        let historyPresenter = makeHistoryPresenter(sessionStore: sessionStore)
        let store = NativeChatShellState(
            chatController: chatController,
            agentController: agentController,
            settingsPresenter: settingsPresenter,
            historyPresenter: historyPresenter,
            selectedTab: selectedTab
        )
        return ScenarioContext(
            store: store,
            chatController: chatController,
            agentController: agentController
        )
    }

    private static func makeChatController(
        client: UITestBackendRequester,
        loader: BackendConversationLoader,
        sessionStore: BackendSessionStore,
        settingsStore: SettingsStore
    ) -> BackendChatController {
        let controller = BackendChatController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
        controller.skipAutomaticBootstrap = true
        return controller
    }

    private static func makeAgentController(
        client: UITestBackendRequester,
        loader: BackendConversationLoader,
        sessionStore: BackendSessionStore,
        settingsStore: SettingsStore
    ) -> BackendAgentController {
        let controller = BackendAgentController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
        controller.skipAutomaticBootstrap = true
        return controller
    }

    private static func makeSettingsPresenter(
        sessionStore: BackendSessionStore,
        client: UITestBackendRequester,
        settingsStore: SettingsStore
    ) -> SettingsPresenter {
        let cacheManager = GeneratedFileCacheManager(
            cacheRootOverride: FileManager.default.temporaryDirectory
                .appendingPathComponent("glassgpt-uitest-cache", isDirectory: true)
        )
        let account = SettingsAccountStore(
            sessionStore: sessionStore,
            client: client,
            signInAction: {
                sessionStore.replace(session: makeSession())
            },
            signOutAction: {
                sessionStore.clear()
            }
        )
        let credentials = SettingsCredentialsStore(client: client, sessionStore: sessionStore)
        return SettingsPresenter(
            account: account,
            credentials: credentials,
            defaults: SettingsDefaultsStore(settingsStore: settingsStore),
            agentDefaults: AgentSettingsDefaultsStore(settingsStore: settingsStore),
            cache: SettingsCacheStore(
                generatedImageCacheLimitString: "250 MB",
                generatedDocumentCacheLimitString: "250 MB",
                cacheManager: cacheManager
            ),
            about: SettingsAboutInfo(appVersionString: "5.0.0 (50000)", platformString: "iOS 26.4")
        )
    }

    private static func makeHistoryPresenter(sessionStore: BackendSessionStore) -> HistoryPresenter {
        let summary = HistoryConversationSummary(
            id: "conv_history_1",
            mode: .chat,
            title: "Release Notes",
            preview: "Synced backend history row",
            updatedAt: .now,
            modelDisplayName: "GPT-5.4 Pro"
        )
        return HistoryPresenter(
            conversations: [summary],
            loadConversations: { [summary] },
            selectConversation: { _, _ in },
            isSignedIn: { sessionStore.isSignedIn }
        )
    }
}
