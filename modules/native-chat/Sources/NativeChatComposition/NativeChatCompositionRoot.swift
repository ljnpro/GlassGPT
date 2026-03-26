import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import Foundation
import GeneratedFilesInfra
#if DEBUG
import NativeChatUI
#endif
import OpenAITransport
import os
import SwiftData

private let compositionSignposter = OSSignposter(subsystem: "GlassGPT", category: "composition")

/// Composition root that wires up all dependencies and creates the ``NativeChatAppStore``.
@MainActor
package struct NativeChatCompositionRoot {
    let modelContext: ModelContext
    let bootstrapPolicy: FeatureBootstrapPolicy

    /// Creates the composition root with the given SwiftData model context and bootstrap policy.
    package init(
        modelContext: ModelContext,
        bootstrapPolicy: FeatureBootstrapPolicy = .live
    ) {
        self.modelContext = modelContext
        self.bootstrapPolicy = bootstrapPolicy
    }

    /// Assembles all services, controllers, and coordinators and returns a fully configured ``NativeChatAppStore``.
    /// Builds the production app store and wires the concrete presenters and controllers.
    package func makeAppStore() -> NativeChatAppStore {
        let signpostID = compositionSignposter.makeSignpostID()
        let signpostState = compositionSignposter.beginInterval("MakeAppStore", id: signpostID)
        defer { compositionSignposter.endInterval("MakeAppStore", signpostState) }

        let settingsStore = SettingsStore()
        let services = makeCompositionServices(settingsStore: settingsStore)

        let chatController = ChatController(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: services.apiKeyStore,
            configurationProvider: services.configurationProvider,
            transport: services.transport,
            serviceFactory: services.serviceFactory,
            bootstrapPolicy: bootstrapPolicy
        )
        let agentController = AgentController(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: services.apiKeyStore,
            requestBuilder: services.requestBuilder,
            responseParser: services.responseParser,
            transport: services.transport,
            serviceFactory: services.serviceFactory,
            bootstrapPolicy: bootstrapPolicy
        )
        let settingsPresenter = makeSettingsPresenter(
            settingsStore: settingsStore,
            apiKeyStore: services.apiKeyStore,
            cloudflareTokenStore: services.cloudflareTokenStore,
            openAIService: services.openAIService,
            requestBuilder: services.requestBuilder,
            transport: services.transport,
            configurationProvider: services.configurationProvider,
            fileDownloadService: services.fileDownloadService,
            applyCloudflareConfiguration: services.applyCloudflareConfiguration
        )
        let store = NativeChatAppStore(
            chatController: chatController,
            agentController: agentController,
            settingsPresenter: settingsPresenter,
            historyPresenter: HistoryPresenter(
                loadConversations: { [] },
                selectConversation: { _ in },
                deleteConversation: { _ in },
                deleteAllConversations: {}
            )
        )
        store.historyPresenter = NativeChatHistoryPresenterFactory.makePresenter(
            modelContext: modelContext,
            chatController: chatController,
            agentController: agentController,
            showChatTab: { store.selectTab(0) },
            showAgentTab: { store.selectTab(1) }
        )

        #if DEBUG
        startDebugMemoryMonitor()
        #endif

        return store
    }
}
