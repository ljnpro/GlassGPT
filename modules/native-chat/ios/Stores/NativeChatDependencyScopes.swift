import SwiftData
import ChatFeatures
import ChatPersistence
import GeneratedFiles

typealias NativeChatServiceScope = ChatFeaturesBoundary.Services<
    OpenAIConfigurationProvider,
    OpenAIRequestBuilder,
    OpenAIResponseParser,
    OpenAIDataTransport,
    OpenAIService
>

typealias NativeChatPersistenceScope = ChatPersistenceBoundary.Scope<
    ModelContext,
    ConversationRepository,
    DraftRepository,
    MessagePersistenceAdapter
>

typealias NativeChatGeneratedFilesScope = GeneratedFilesBoundary.Scope<GeneratedFileCoordinator>

@MainActor
struct NativeChatFeatureDependencies {
    let scope: ChatFeaturesBoundary.Scope<
        NativeChatServiceScope,
        NativeChatPersistenceScope,
        NativeChatGeneratedFilesScope,
        SettingsStore,
        APIKeyStore,
        BackgroundTaskCoordinator
    >
    let serviceFactory: @MainActor () -> OpenAIService

    init(
        modelContext: ModelContext,
        settingsStore: SettingsStore,
        apiKeyStore: APIKeyStore,
        configurationProvider: OpenAIConfigurationProvider,
        requestBuilder: OpenAIRequestBuilder,
        responseParser: OpenAIResponseParser,
        transport: OpenAIDataTransport,
        openAIService: OpenAIService,
        serviceFactory: @escaping @MainActor () -> OpenAIService,
        backgroundTasks: BackgroundTaskCoordinator = BackgroundTaskCoordinator(),
        generatedFileCoordinator: GeneratedFileCoordinator = GeneratedFileCoordinator(),
        messagePersistence: MessagePersistenceAdapter = MessagePersistenceAdapter()
    ) {
        self.scope = .init(
            services: .init(
                configurationProvider: configurationProvider,
                requestBuilder: requestBuilder,
                responseParser: responseParser,
                transport: transport,
                service: openAIService
            ),
            persistence: .init(
                modelContext: modelContext,
                conversationRepository: ConversationRepository(modelContext: modelContext),
                draftRepository: DraftRepository(modelContext: modelContext),
                messagePersistence: messagePersistence
            ),
            generatedFiles: .init(coordinator: generatedFileCoordinator),
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            backgroundTasks: backgroundTasks
        )
        self.serviceFactory = serviceFactory
    }

    var services: NativeChatServiceScope { scope.services }
    var persistence: NativeChatPersistenceScope { scope.persistence }
    var generatedFiles: NativeChatGeneratedFilesScope { scope.generatedFiles }
    var settingsStore: SettingsStore { scope.settingsStore }
    var apiKeyStore: APIKeyStore { scope.apiKeyStore }
    var backgroundTasks: BackgroundTaskCoordinator { scope.backgroundTasks }
}

@MainActor
struct NativeChatSettingsDependencies {
    let services: NativeChatServiceScope
    let settingsStore: SettingsStore
    let apiKeyStore: APIKeyStore
    private let setCloudflareGatewayEnabledHandler: @MainActor (Bool) -> Void

    init(
        settingsStore: SettingsStore,
        apiKeyStore: APIKeyStore,
        configurationProvider: OpenAIConfigurationProvider,
        requestBuilder: OpenAIRequestBuilder,
        responseParser: OpenAIResponseParser,
        transport: OpenAIDataTransport,
        openAIService: OpenAIService
    ) {
        var mutableConfigurationProvider = configurationProvider
        self.services = .init(
            configurationProvider: configurationProvider,
            requestBuilder: requestBuilder,
            responseParser: responseParser,
            transport: transport,
            service: openAIService
        )
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.setCloudflareGatewayEnabledHandler = { isEnabled in
            mutableConfigurationProvider.useCloudflareGateway = isEnabled
        }
    }

    func setCloudflareGatewayEnabled(_ isEnabled: Bool) {
        setCloudflareGatewayEnabledHandler(isEnabled)
    }
}
