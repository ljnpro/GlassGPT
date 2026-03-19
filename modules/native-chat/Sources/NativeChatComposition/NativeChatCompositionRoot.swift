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
        let settingsPresenter = makeSettingsPresenter(
            settingsStore: settingsStore,
            apiKeyStore: services.apiKeyStore,
            openAIService: services.openAIService,
            requestBuilder: services.requestBuilder,
            transport: services.transport,
            configurationProvider: services.configurationProvider,
            fileDownloadService: services.fileDownloadService
        )
        let store = NativeChatAppStore(
            chatController: chatController,
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
            showChatTab: { store.selectedTab = 0 }
        )

        #if DEBUG
        startDebugMemoryMonitor()
        #endif

        return store
    }

    private func makeCompositionServices(settingsStore: SettingsStore) -> CompositionServices {
        let apiKeyStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
            )
        )
        let configurationProvider = makeConfigurationProvider(settingsStore: settingsStore)
        let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let responseParser = OpenAIResponseParser()
        let transport = OpenAIURLSessionTransport(
            session: OpenAITransportSessionFactory.makeRequestSession()
        )
        let serviceFactory: @MainActor () -> OpenAIService = {
            OpenAIService(
                requestBuilder: requestBuilder,
                responseParser: responseParser,
                streamClient: SSEEventStream(),
                transport: transport
            )
        }

        return CompositionServices(
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            requestBuilder: requestBuilder,
            transport: transport,
            serviceFactory: serviceFactory,
            openAIService: serviceFactory(),
            fileDownloadService: FileDownloadService(configurationProvider: configurationProvider)
        )
    }

    #if DEBUG
    /// Starts a repeating timer that logs available memory every 30 seconds and warns when below 100 MB.
    private func startDebugMemoryMonitor() {
        let logger = Loggers.diagnostics
        let memoryWarningThreshold = 100 * 1024 * 1024
        Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                let available = os_proc_available_memory()
                LaunchTimingStore.shared.availableMemoryBytes = UInt64(available)
                if available < memoryWarningThreshold {
                    logger.error("[Memory] Available memory critically low: \(available / 1024 / 1024) MB")
                }
            }
        }
    }
    #endif

    private func makeConfigurationProvider(settingsStore: SettingsStore) -> DefaultOpenAIConfigurationProvider {
        DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL,
            cloudflareGatewayBaseURL: resolvedConfigurationValue(
                infoKey: "CloudflareGatewayBaseURL",
                environmentKey: "CLOUDFLARE_GATEWAY_BASE_URL",
                fallback: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL
            ),
            cloudflareAIGToken: resolvedConfigurationValue(
                infoKey: "CloudflareAIGToken",
                environmentKey: "CLOUDFLARE_AIG_TOKEN",
                fallback: ""
            ),
            useCloudflareGateway: settingsStore.cloudflareGatewayEnabled
        )
    }

    private func resolvedConfigurationValue(
        infoKey: String,
        environmentKey: String,
        fallback: String
    ) -> String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !infoValue.isEmpty {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey],
           !environmentValue.isEmpty {
            return environmentValue
        }

        return fallback
    }
}

private struct CompositionServices {
    let apiKeyStore: PersistedAPIKeyStore
    let configurationProvider: DefaultOpenAIConfigurationProvider
    let requestBuilder: OpenAIRequestBuilder
    let transport: OpenAIURLSessionTransport
    let serviceFactory: @MainActor () -> OpenAIService
    let openAIService: OpenAIService
    let fileDownloadService: FileDownloadService
}
