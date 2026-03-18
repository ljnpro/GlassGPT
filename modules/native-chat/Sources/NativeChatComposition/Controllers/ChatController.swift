import SwiftUI
import SwiftData
import UIKit
import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import ChatRuntimePorts
import ChatRuntimeWorkflows
import GeneratedFilesInfra
import OpenAITransport

@Observable
@MainActor
package final class ChatController {

    // MARK: - State

    var messages: [Message] = []
    package var currentStreamingText: String = ""
    package var currentThinkingText: String = ""
    package var isStreaming: Bool = false
    package var isThinking: Bool = false
    var isRecovering: Bool = false
    var isRestoringConversation: Bool = false
    var selectedModel: ModelType = .gpt5_4 {
        didSet {
            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var reasoningEffort: ReasoningEffort = .high {
        didSet {
            guard selectedModel.availableEfforts.contains(reasoningEffort) else {
                reasoningEffort = selectedModel.defaultEffort
                return
            }
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var backgroundModeEnabled: Bool = false {
        didSet {
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var serviceTier: ServiceTier = .standard {
        didSet {
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    package var currentConversation: ChatPersistenceSwiftData.Conversation?
    var errorMessage: String?
    var selectedImageData: Data?

    // Tool call state
    package var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []
    var liveFilePathAnnotations: [FilePathAnnotation] = []

    // File attachments pending send
    var pendingAttachments: [FileAttachment] = []

    // File preview state
    let filePreviewStore = ChatPresentation.FilePreviewStore()

    // MARK: - Dependencies

    @ObservationIgnored
    let modelContext: ModelContext
    @ObservationIgnored
    let settingsStore: SettingsStore
    @ObservationIgnored
    let apiKeyStore: PersistedAPIKeyStore
    @ObservationIgnored
    let configurationProvider: OpenAIConfigurationProvider
    @ObservationIgnored
    let requestBuilder: OpenAIRequestBuilder
    @ObservationIgnored
    let responseParser: OpenAIResponseParser
    @ObservationIgnored
    let transport: OpenAIDataTransport
    @ObservationIgnored
    let openAIService: OpenAIService
    @ObservationIgnored
    let conversationRepository: ConversationRepository
    @ObservationIgnored
    let draftRepository: DraftRepository
    @ObservationIgnored
    let generatedFileCoordinator: GeneratedFileCoordinator
    @ObservationIgnored
    let messagePersistence: ChatPersistenceSwiftData.MessagePersistenceAdapter
    @ObservationIgnored
    let backgroundTaskCoordinator: BackgroundTaskCoordinator
    @ObservationIgnored
    let fileDownloadService: GeneratedFilesInfra.FileDownloadService
    @ObservationIgnored
    let serviceFactory: @MainActor () -> OpenAIService

    // Visible live session state
    var draftMessage: Message?
    var lastSequenceNumber: Int?
    var activeRequestModel: ModelType?
    var activeRequestEffort: ReasoningEffort?
    var activeRequestUsesBackgroundMode = false
    var activeRequestServiceTier: ServiceTier = .standard
    var isApplyingStoredConversationConfiguration = false
    var isApplyingConversationConfigurationBatch = false
    var didCompleteLaunchBootstrap = false
    var visibleRecoveryPhase: RecoveryPhase = .idle
    @ObservationIgnored
    let sessionRegistry = ChatSessionRegistry()
    @ObservationIgnored
    lazy var runtimeRegistry = RuntimeRegistryActor()
    @ObservationIgnored
    lazy var chatSceneController = ChatSceneController(
        registry: runtimeRegistry,
        preparationPort: self
    )
    // MARK: - Init

    package init(
        modelContext: ModelContext,
        settingsStore: SettingsStore = .shared,
        apiKeyStore: PersistedAPIKeyStore = PersistedAPIKeyStore(
            backend: KeychainAPIKeyBackend(
                service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
            )
        ),
        configurationProvider: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared,
        transport: OpenAIDataTransport = OpenAIURLSessionTransport(),
        serviceFactory: (@MainActor () -> OpenAIService)? = nil,
        bootstrapPolicy: FeatureBootstrapPolicy = .live
    ) {
        let resolvedRequestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let resolvedResponseParser = OpenAIResponseParser()
        let resolvedServiceFactory = serviceFactory ?? {
            OpenAIService(
                requestBuilder: resolvedRequestBuilder,
                responseParser: resolvedResponseParser,
                streamClient: SSEEventStream(),
                transport: transport
            )
        }
        let resolvedOpenAIService = resolvedServiceFactory()

        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.configurationProvider = configurationProvider
        self.requestBuilder = resolvedRequestBuilder
        self.responseParser = resolvedResponseParser
        self.transport = transport
        self.openAIService = resolvedOpenAIService
        self.conversationRepository = ConversationRepository(modelContext: modelContext)
        self.draftRepository = DraftRepository(modelContext: modelContext)
        self.generatedFileCoordinator = GeneratedFileCoordinator()
        self.messagePersistence = ChatPersistenceSwiftData.MessagePersistenceAdapter()
        self.backgroundTaskCoordinator = BackgroundTaskCoordinator()
        self.fileDownloadService = GeneratedFilesInfra.FileDownloadService(configurationProvider: configurationProvider)
        self.serviceFactory = resolvedServiceFactory
        self.didCompleteLaunchBootstrap = !bootstrapPolicy.runLaunchTasks
        loadDefaultsFromSettings()
        if bootstrapPolicy.restoreLastConversation {
            restoreLastConversationIfAvailable()
        }
        syncConversationProjection()

        if bootstrapPolicy.setupLifecycleObservers {
            setupLifecycleObservers()
        }

        if bootstrapPolicy.runLaunchTasks {
            Task { @MainActor in
                await recoverIncompleteMessagesInCurrentConversation()
                await recoverIncompleteMessages()
                await resendOrphanedDrafts()
                self.didCompleteLaunchBootstrap = true
                await generateTitlesForUntitledConversations()
            }
        }
    }

    package convenience init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            settingsStore: .shared,
            apiKeyStore: PersistedAPIKeyStore(
                backend: KeychainAPIKeyBackend(
                    service: KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
                )
            ),
            bootstrapPolicy: .live
        )
    }
}
