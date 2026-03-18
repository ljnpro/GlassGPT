import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData

@MainActor
final class ChatControllerServices {
    let modelContext: ModelContext
    let settingsStore: SettingsStore
    let apiKeyStore: PersistedAPIKeyStore
    let configurationProvider: OpenAIConfigurationProvider
    let requestBuilder: OpenAIRequestBuilder
    let responseParser: OpenAIResponseParser
    let transport: OpenAIDataTransport
    let openAIService: OpenAIService
    let conversationRepository: ConversationRepository
    let draftRepository: DraftRepository
    let generatedFileCoordinator: GeneratedFileCoordinator
    let messagePersistence: MessagePersistenceAdapter
    let backgroundTaskCoordinator: BackgroundTaskCoordinator
    let fileDownloadService: FileDownloadService
    let serviceFactory: @MainActor () -> OpenAIService

    init(
        modelContext: ModelContext,
        settingsStore: SettingsStore,
        apiKeyStore: PersistedAPIKeyStore,
        configurationProvider: OpenAIConfigurationProvider,
        requestBuilder: OpenAIRequestBuilder,
        responseParser: OpenAIResponseParser,
        transport: OpenAIDataTransport,
        openAIService: OpenAIService,
        serviceFactory: @escaping @MainActor () -> OpenAIService
    ) {
        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.configurationProvider = configurationProvider
        self.requestBuilder = requestBuilder
        self.responseParser = responseParser
        self.transport = transport
        self.openAIService = openAIService
        self.conversationRepository = ConversationRepository(modelContext: modelContext)
        self.draftRepository = DraftRepository(modelContext: modelContext)
        self.generatedFileCoordinator = GeneratedFileCoordinator()
        self.messagePersistence = MessagePersistenceAdapter()
        self.backgroundTaskCoordinator = BackgroundTaskCoordinator()
        self.fileDownloadService = FileDownloadService(configurationProvider: configurationProvider)
        self.serviceFactory = serviceFactory
    }
}
