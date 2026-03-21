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
        let keychainService = KeychainAPIKeyBackend.defaultServiceIdentifier(
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
        let apiKeyStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: keychainService
            )
        )
        let cloudflareTokenStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: keychainService,
                account: KeychainAPIKeyBackend.cloudflareAIGTokenAccount
            )
        )
        let cloudflareDefaults = makeCloudflareConfigurationDefaults()
        let configurationProvider = makeConfigurationProvider(
            settingsStore: settingsStore,
            cloudflareTokenStore: cloudflareTokenStore,
            defaults: cloudflareDefaults
        )
        let applyCloudflareConfiguration: @MainActor () -> Void = {
            self.applyCloudflareConfiguration(
                to: configurationProvider,
                settingsStore: settingsStore,
                cloudflareTokenStore: cloudflareTokenStore,
                defaults: cloudflareDefaults
            )
        }
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
            cloudflareTokenStore: cloudflareTokenStore,
            configurationProvider: configurationProvider,
            requestBuilder: requestBuilder,
            transport: transport,
            serviceFactory: serviceFactory,
            openAIService: serviceFactory(),
            fileDownloadService: FileDownloadService(configurationProvider: configurationProvider),
            applyCloudflareConfiguration: applyCloudflareConfiguration
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

    private func makeConfigurationProvider(
        settingsStore: SettingsStore,
        cloudflareTokenStore: PersistedAPIKeyStore,
        defaults: CloudflareRuntimeConfigurationDefaults
    ) -> DefaultOpenAIConfigurationProvider {
        let provider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL,
            cloudflareGatewayBaseURL: defaults.gatewayBaseURL,
            cloudflareAIGToken: defaults.gatewayToken,
            useCloudflareGateway: settingsStore.cloudflareGatewayEnabled
        )
        applyCloudflareConfiguration(
            to: provider,
            settingsStore: settingsStore,
            cloudflareTokenStore: cloudflareTokenStore,
            defaults: defaults
        )
        return provider
    }

    private func makeCloudflareConfigurationDefaults() -> CloudflareRuntimeConfigurationDefaults {
        CloudflareRuntimeConfigurationDefaults(
            gatewayBaseURL: resolvedConfigurationValue(
                infoKey: "CloudflareGatewayBaseURL",
                environmentKey: "CLOUDFLARE_GATEWAY_BASE_URL",
                fallback: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL
            ),
            gatewayToken: resolvedConfigurationValue(
                infoKey: "CloudflareAIGToken",
                environmentKey: "CLOUDFLARE_AIG_TOKEN",
                fallback: DefaultOpenAIConfigurationProvider.defaultCloudflareAIGToken
            )
        )
    }

    private func applyCloudflareConfiguration(
        to provider: DefaultOpenAIConfigurationProvider,
        settingsStore: SettingsStore,
        cloudflareTokenStore: PersistedAPIKeyStore,
        defaults: CloudflareRuntimeConfigurationDefaults
    ) {
        let persistedCustomBaseURL = settingsStore.customCloudflareGatewayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedCustomToken = cloudflareTokenStore.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch settingsStore.cloudflareGatewayConfigurationMode {
        case .default:
            provider.cloudflareGatewayBaseURL = defaults.gatewayBaseURL
            provider.cloudflareAIGToken = defaults.gatewayToken
        case .custom:
            provider.cloudflareGatewayBaseURL = persistedCustomBaseURL.isEmpty
                ? defaults.gatewayBaseURL
                : persistedCustomBaseURL
            provider.cloudflareAIGToken = persistedCustomToken.isEmpty
                ? defaults.gatewayToken
                : persistedCustomToken
        }

        provider.useCloudflareGateway = settingsStore.cloudflareGatewayEnabled
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
    let cloudflareTokenStore: PersistedAPIKeyStore
    let configurationProvider: DefaultOpenAIConfigurationProvider
    let requestBuilder: OpenAIRequestBuilder
    let transport: OpenAIURLSessionTransport
    let serviceFactory: @MainActor () -> OpenAIService
    let openAIService: OpenAIService
    let fileDownloadService: FileDownloadService
    let applyCloudflareConfiguration: @MainActor () -> Void
}

private struct CloudflareRuntimeConfigurationDefaults {
    let gatewayBaseURL: String
    let gatewayToken: String
}
