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
import SwiftData
import SwiftUI
import UIKit

/// Central controller managing the active chat session, message state, streaming, and recovery.
///
/// Owns a set of single-responsibility coordinators that handle conversation management,
/// session lifecycle, file interactions, streaming, and recovery.
@Observable
@MainActor
package final class ChatController {
    // MARK: - State

    var messages: [Message] = []
    /// The text being streamed from the assistant's current response.
    package var currentStreamingText = ""
    /// The reasoning/thinking text being emitted by the model.
    package var currentThinkingText = ""
    /// Whether the assistant is actively streaming a response.
    package var isStreaming = false
    /// Whether the model is actively in a reasoning phase.
    package var isThinking = false
    var isRecovering = false
    var isRestoringConversation = false
    var selectedModel: ModelType = .gpt5_4 {
        didSet {
            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }
            guard !isApplyingStoredConversationConfiguration, !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }

    var reasoningEffort: ReasoningEffort = .high {
        didSet {
            guard selectedModel.availableEfforts.contains(reasoningEffort) else {
                reasoningEffort = selectedModel.defaultEffort
                return
            }
            guard !isApplyingStoredConversationConfiguration, !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }

    var backgroundModeEnabled = false {
        didSet {
            guard !isApplyingStoredConversationConfiguration, !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }

    var serviceTier: ServiceTier = .standard {
        didSet {
            guard !isApplyingStoredConversationConfiguration, !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }

    /// The currently loaded conversation, if any.
    package var currentConversation: ChatPersistenceSwiftData.Conversation?
    var errorMessage: String?
    var selectedImageData: Data?

    // Tool call state
    /// Tool calls currently being executed by the model.
    package var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []
    var liveFilePathAnnotations: [FilePathAnnotation] = []

    /// File attachments pending send
    var pendingAttachments: [FileAttachment] = []

    /// File preview state
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
    let messagePersistence: MessagePersistenceAdapter
    @ObservationIgnored
    let backgroundTaskCoordinator: BackgroundTaskCoordinator
    @ObservationIgnored
    let fileDownloadService: FileDownloadService
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
    @ObservationIgnored
    let sessionRegistry = ChatSessionRegistry()
    @ObservationIgnored
    lazy var runtimeRegistry = RuntimeRegistryActor()
    @ObservationIgnored
    let coordinatorBox = ChatControllerCoordinatorBox()
    @ObservationIgnored
    let generatedFilePrefetchRegistry = GeneratedFilePrefetchRegistry()

    // MARK: - Init

    /// Creates a chat controller with the given persistence context, stores, and transport layer.
    package init(
        modelContext: ModelContext,
        settingsStore: SettingsStore,
        apiKeyStore: PersistedAPIKeyStore,
        configurationProvider: OpenAIConfigurationProvider,
        transport: OpenAIDataTransport,
        fileDownloadService: FileDownloadService? = nil,
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
        requestBuilder = resolvedRequestBuilder
        responseParser = resolvedResponseParser
        self.transport = transport
        openAIService = resolvedOpenAIService
        conversationRepository = ConversationRepository(modelContext: modelContext)
        draftRepository = DraftRepository(modelContext: modelContext)
        generatedFileCoordinator = GeneratedFileCoordinator()
        messagePersistence = MessagePersistenceAdapter()
        backgroundTaskCoordinator = BackgroundTaskCoordinator()
        self.fileDownloadService = fileDownloadService ?? FileDownloadService(configurationProvider: configurationProvider)
        self.serviceFactory = resolvedServiceFactory
        didCompleteLaunchBootstrap = !bootstrapPolicy.runLaunchTasks
        conversationCoordinator.loadDefaultsFromSettings()
        if bootstrapPolicy.restoreLastConversation {
            conversationCoordinator.restoreLastConversationIfAvailable()
        }
        syncConversationProjection()

        if bootstrapPolicy.setupLifecycleObservers {
            lifecycleCoordinator.setupLifecycleObservers()
        }

        if bootstrapPolicy.runLaunchTasks {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await recoveryMaintenanceCoordinator.recoverIncompleteMessagesInCurrentConversation()
                await recoveryMaintenanceCoordinator.recoverIncompleteMessages()
                await recoveryMaintenanceCoordinator.resendOrphanedDrafts()
                didCompleteLaunchBootstrap = true
                await lifecycleCoordinator.generateTitlesForUntitledConversations()
            }
        }
    }

    deinit {
        let backgroundTaskCoordinator = backgroundTaskCoordinator
        let sessionRegistry = sessionRegistry
        let generatedFilePrefetchRegistry = generatedFilePrefetchRegistry

        Task { @MainActor in
            backgroundTaskCoordinator.endBackgroundTask()
            sessionRegistry.removeAll { execution in
                execution.task?.cancel()
                execution.service.cancelStream()
            }
            generatedFilePrefetchRegistry.cancelAll()
        }
    }
}
