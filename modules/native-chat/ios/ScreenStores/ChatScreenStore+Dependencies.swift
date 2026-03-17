import SwiftData

extension ChatScreenStore {
    var sessionRegistry: ChatSessionRegistry {
        conversationRuntime.sessionStateStore.registry
    }

    var configurationProvider: OpenAIConfigurationProvider {
        dependencies.services.configurationProvider
    }

    var requestBuilder: OpenAIRequestBuilder {
        dependencies.services.requestBuilder
    }

    var responseParser: OpenAIResponseParser {
        dependencies.services.responseParser
    }

    var transport: OpenAIDataTransport {
        dependencies.services.transport
    }

    var openAIService: OpenAIService {
        dependencies.services.service
    }

    var settingsStore: SettingsStore {
        dependencies.settingsStore
    }

    var apiKeyStore: APIKeyStore {
        dependencies.apiKeyStore
    }

    var conversationRepository: ConversationRepository {
        dependencies.persistence.conversationRepository
    }

    var draftRepository: DraftRepository {
        dependencies.persistence.draftRepository
    }

    var generatedFileCoordinator: GeneratedFileCoordinator {
        dependencies.generatedFiles.coordinator
    }

    var messagePersistence: MessagePersistenceAdapter {
        dependencies.persistence.messagePersistence
    }

    var backgroundTaskCoordinator: BackgroundTaskCoordinator {
        dependencies.backgroundTasks
    }

    var serviceFactory: @MainActor () -> OpenAIService {
        dependencies.serviceFactory
    }

    var modelContext: ModelContext {
        dependencies.persistence.modelContext
    }
}
