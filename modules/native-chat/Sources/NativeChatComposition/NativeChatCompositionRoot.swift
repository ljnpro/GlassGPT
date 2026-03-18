import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData

@MainActor
package struct NativeChatCompositionRoot {
    let modelContext: ModelContext
    let bootstrapPolicy: FeatureBootstrapPolicy

    package init(
        modelContext: ModelContext,
        bootstrapPolicy: FeatureBootstrapPolicy = .live
    ) {
        self.modelContext = modelContext
        self.bootstrapPolicy = bootstrapPolicy
    }

    package func makeAppStore() -> NativeChatAppStore {
        if let bootstrap = UITestScenarioLoader.makeBootstrap(modelContext: modelContext) {
            let store = NativeChatAppStore(
                chatController: bootstrap.chatController,
                settingsPresenter: bootstrap.settingsPresenter,
                historyPresenter: HistoryPresenter(
                    loadConversations: { [] },
                    selectConversation: { _ in },
                    deleteConversation: { _ in },
                    deleteAllConversations: {}
                ),
                selectedTab: bootstrap.initialTab,
                uiTestScenario: bootstrap.scenario,
                uiTestPreviewItem: bootstrap.initialPreviewItem
            )
            let historyCoordinator = NativeChatHistoryCoordinator(
                modelContext: modelContext,
                chatController: bootstrap.chatController,
                showChatTab: { store.selectedTab = 0 }
            )
            store.historyPresenter = historyCoordinator.makePresenter()
            return store
        }

        let settingsStore = SettingsStore.shared
        configureSharedServices()

        let apiKeyStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
            )
        )
        let configurationProvider = DefaultOpenAIConfigurationProvider.shared
        let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let responseParser = OpenAIResponseParser()
        let transport = OpenAIURLSessionTransport()
        let serviceFactory: @MainActor () -> OpenAIService = {
            OpenAIService(
                requestBuilder: requestBuilder,
                responseParser: responseParser,
                streamClient: SSEEventStream(),
                transport: transport
            )
        }
        let openAIService = serviceFactory()
        let fileDownloadService = FileDownloadService(configurationProvider: configurationProvider)

        let chatController = ChatController(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            transport: transport,
            serviceFactory: serviceFactory,
            bootstrapPolicy: bootstrapPolicy
        )
        let settingsPresenter = makeSettingsPresenter(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            openAIService: openAIService,
            requestBuilder: requestBuilder,
            transport: transport,
            configurationProvider: configurationProvider,
            fileDownloadService: fileDownloadService
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
        let historyCoordinator = NativeChatHistoryCoordinator(
            modelContext: modelContext,
            chatController: chatController,
            showChatTab: { store.selectedTab = 0 }
        )
        store.historyPresenter = historyCoordinator.makePresenter()
        return store
    }

    private func configureSharedServices() {
        HapticService.isEnabledProvider = { SettingsStore.shared.hapticEnabled }
        DefaultOpenAIConfigurationProvider.shared.configure(
            directOpenAIBaseURL: {
                DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL
            },
            cloudflareGatewayBaseURL: {
                if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareGatewayBaseURL") as? String,
                   !infoValue.isEmpty {
                    return infoValue
                }

                if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_GATEWAY_BASE_URL"],
                   !environmentValue.isEmpty {
                    return environmentValue
                }

                return DefaultOpenAIConfigurationProvider.bundledCloudflareGatewayBaseURL
            },
            cloudflareAIGToken: {
                if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareAIGToken") as? String,
                   !infoValue.isEmpty {
                    return infoValue
                }

                if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_AIG_TOKEN"],
                   !environmentValue.isEmpty {
                    return environmentValue
                }

                return DefaultOpenAIConfigurationProvider.bundledCloudflareAIGToken
            },
            useCloudflareGateway: {
                SettingsStore.shared.cloudflareGatewayEnabled
            },
            setUseCloudflareGateway: { enabled in
                SettingsStore.shared.cloudflareGatewayEnabled = enabled
            }
        )
    }
}
