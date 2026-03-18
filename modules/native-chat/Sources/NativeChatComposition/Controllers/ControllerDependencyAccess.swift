import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import GeneratedFilesInfra
import OpenAITransport
import SwiftData

@MainActor
extension ChatController {
    package var modelContext: ModelContext { services.modelContext }
    var settingsStore: SettingsStore { services.settingsStore }
    var apiKeyStore: PersistedAPIKeyStore { services.apiKeyStore }
    var configurationProvider: OpenAIConfigurationProvider { services.configurationProvider }
    var requestBuilder: OpenAIRequestBuilder { services.requestBuilder }
    var responseParser: OpenAIResponseParser { services.responseParser }
    var transport: OpenAIDataTransport { services.transport }
    var openAIService: OpenAIService { services.openAIService }
    var conversationRepository: ConversationRepository { services.conversationRepository }
    var draftRepository: DraftRepository { services.draftRepository }
    var generatedFileCoordinator: GeneratedFileCoordinator { services.generatedFileCoordinator }
    var messagePersistence: MessagePersistenceAdapter { services.messagePersistence }
    var backgroundTaskCoordinator: BackgroundTaskCoordinator { services.backgroundTaskCoordinator }
    var fileDownloadService: FileDownloadService { services.fileDownloadService }
    var hapticsEnabled: Bool { settingsStore.hapticEnabled }
    var hapticService: HapticService { services.hapticService }
    var serviceFactory: @MainActor () -> OpenAIService { services.serviceFactory }
}
