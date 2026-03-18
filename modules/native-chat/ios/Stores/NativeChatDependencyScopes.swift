import SwiftData

struct NativeChatServiceDependencies {
    let configurationProvider: OpenAIConfigurationProvider
    let requestBuilder: OpenAIRequestBuilder
    let responseParser: OpenAIResponseParser
    let transport: OpenAIDataTransport
    let service: OpenAIService
}

struct NativeChatPersistenceDependencies {
    let modelContext: ModelContext
    let conversationRepository: ConversationRepository
    let draftRepository: DraftRepository
    let messagePersistence: MessagePersistenceAdapter
}

struct NativeChatGeneratedFilesDependencies {
    let coordinator: GeneratedFileCoordinator
}

@MainActor
struct NativeChatFeatureDependencies {
    let services: NativeChatServiceDependencies
    let persistence: NativeChatPersistenceDependencies
    let generatedFiles: NativeChatGeneratedFilesDependencies
    let settingsStore: SettingsStore
    let apiKeyStore: APIKeyStore
    let backgroundTasks: BackgroundTaskCoordinator
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
        self.services = .init(
            configurationProvider: configurationProvider,
            requestBuilder: requestBuilder,
            responseParser: responseParser,
            transport: transport,
            service: openAIService
        )
        self.persistence = .init(
            modelContext: modelContext,
            conversationRepository: ConversationRepository(modelContext: modelContext),
            draftRepository: DraftRepository(modelContext: modelContext),
            messagePersistence: messagePersistence
        )
        self.generatedFiles = .init(coordinator: generatedFileCoordinator)
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.backgroundTasks = backgroundTasks
        self.serviceFactory = serviceFactory
    }
}

@MainActor
struct NativeChatSettingsDependencies {
    let services: NativeChatServiceDependencies
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
