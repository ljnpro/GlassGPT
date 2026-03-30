import BackendAuth
import BackendClient
import BackendSessionPersistence
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import os
import SwiftData

private let compositionSignposter = OSSignposter(subsystem: "GlassGPT", category: "composition")

/// Composition root that wires up all dependencies and creates the ``NativeChatShellState``.
@MainActor
package struct NativeChatCompositionRoot {
    let modelContext: ModelContext

    /// Creates the composition root with the given SwiftData model context.
    package init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Assembles all services, controllers, and coordinators and returns a fully configured ``NativeChatShellState``.
    /// Builds the production app store and wires the concrete presenters and controllers.
    package func makeAppStore() -> NativeChatShellState {
        let signpostID = compositionSignposter.makeSignpostID()
        let signpostState = compositionSignposter.beginInterval("MakeAppStore", id: signpostID)
        defer { compositionSignposter.endInterval("MakeAppStore", signpostState) }

        let settingsStore = SettingsStore()
        let services = makeCompositionServices()
        let deviceIdentityStore = BackendDeviceIdentityStore()
        let appleSignInCoordinator = AppleSignInCoordinator()
        let projectionStore = BackendProjectionStore(
            cacheRepository: ProjectionCacheRepository(modelContext: modelContext),
            cursorStore: SyncCursorStore()
        )
        let conversationLoader = BackendConversationLoader(
            client: services.backendClient,
            projectionStore: projectionStore,
            sessionStore: services.backendSessionStore
        )

        let chatController = BackendChatController(
            client: services.backendClient,
            loader: conversationLoader,
            sessionStore: services.backendSessionStore,
            settingsStore: settingsStore
        )
        let agentController = BackendAgentController(
            client: services.backendClient,
            loader: conversationLoader,
            sessionStore: services.backendSessionStore,
            settingsStore: settingsStore
        )
        let filePreviewStore = FilePreviewStore()
        let generatedFileInteractionCoordinator = GeneratedFileInteractionCoordinator(
            client: services.backendClient,
            cacheManager: services.cacheManager,
            filePreviewStore: filePreviewStore
        )
        let store = NativeChatShellState(
            chatController: chatController,
            agentController: agentController,
            settingsPresenter: makeSettingsPresenter(
                settingsStore: settingsStore,
                backendSessionStore: services.backendSessionStore,
                backendClient: services.backendClient,
                cacheManager: services.cacheManager
            ),
            historyPresenter: HistoryPresenter(
                loadConversations: { [] },
                selectConversation: { _, _ in }
            ),
            filePreviewStore: filePreviewStore,
            generatedFileInteractionCoordinator: generatedFileInteractionCoordinator
        )
        store.historyPresenter = NativeChatHistoryPresenterFactory.makePresenter(
            modelContext: modelContext,
            currentAccountID: { services.backendSessionStore.currentUser?.id },
            loadChatConversation: { conversationID in
                chatController.loadConversation(serverID: conversationID)
            },
            loadAgentConversation: { conversationID in
                agentController.loadConversation(serverID: conversationID)
            },
            showChatTab: { store.selectTab(0) },
            showAgentTab: { store.selectTab(1) },
            showSettingsTab: { store.selectTab(3) }
        )
        let accountSessionCoordinator = AccountSessionCoordinator(
            appleSignInCoordinator: appleSignInCoordinator,
            deviceIdentityStore: deviceIdentityStore,
            client: services.backendClient,
            loader: conversationLoader,
            sessionStore: services.backendSessionStore,
            reloadProjectionSurfaces: {
                await chatController.bootstrap()
                await agentController.bootstrap()
            },
            resetProjectionSurfaces: {
                chatController.startNewConversation()
                agentController.startNewConversation()
            },
            refreshHistory: {
                store.historyPresenter.refresh()
            }
        )
        store.settingsPresenter = makeSettingsPresenter(
            settingsStore: settingsStore,
            backendSessionStore: services.backendSessionStore,
            backendClient: services.backendClient,
            cacheManager: services.cacheManager,
            signInAction: {
                try await accountSessionCoordinator.signIn()
                await store.settingsPresenter.credentials.refreshStatus()
            },
            signOutAction: {
                await accountSessionCoordinator.signOut()
                await store.settingsPresenter.credentials.refreshStatus()
            }
        )

        #if DEBUG
        startDebugMemoryMonitor()
        #endif

        return store
    }
}
