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
/// Central controller managing the active chat session, message state, streaming, and recovery.
///
/// Owns a set of single-responsibility coordinators that handle conversation management,
/// session lifecycle, file interactions, streaming, and recovery.
package final class ChatController {

    // MARK: - State

    var messages: [Message] = []
    /// The text being streamed from the assistant's current response.
    package var currentStreamingText: String = ""
    /// The reasoning/thinking text being emitted by the model.
    package var currentThinkingText: String = ""
    /// Whether the assistant is actively streaming a response.
    package var isStreaming: Bool = false
    /// Whether the model is actively in a reasoning phase.
    package var isThinking: Bool = false
    var isRecovering: Bool = false
    var isRestoringConversation: Bool = false
    var selectedModel: ModelType = .gpt5_4 {
        didSet {
            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }
    var reasoningEffort: ReasoningEffort = .high {
        didSet {
            guard selectedModel.availableEfforts.contains(reasoningEffort) else {
                reasoningEffort = selectedModel.defaultEffort
                return
            }
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }
    var backgroundModeEnabled: Bool = false {
        didSet {
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            conversationCoordinator.syncConversationConfiguration()
        }
    }
    var serviceTier: ServiceTier = .standard {
        didSet {
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
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

    // File attachments pending send
    var pendingAttachments: [FileAttachment] = []

    // File preview state
    let filePreviewStore = ChatPresentation.FilePreviewStore()

    // MARK: - Dependencies

    @ObservationIgnored
    let services: ChatControllerServices

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
    lazy var sendCoordinator = ChatSendCoordinator(controller: self)
    @ObservationIgnored
    /// Coordinator managing conversation CRUD, configuration sync, and message projection.
    package lazy var conversationCoordinator = ChatConversationCoordinator(controller: self)
    @ObservationIgnored
    lazy var sessionCoordinator = ChatSessionCoordinator(controller: self)
    @ObservationIgnored
    lazy var fileInteractionCoordinator = ChatFileInteractionCoordinator(controller: self)
    @ObservationIgnored
    lazy var lifecycleCoordinator = ChatLifecycleCoordinator(controller: self)
    @ObservationIgnored
    lazy var streamingCoordinator = ChatStreamingCoordinator(controller: self)
    @ObservationIgnored
    lazy var recoveryCoordinator = ChatRecoveryCoordinator(controller: self)
    @ObservationIgnored
    lazy var recoveryResultApplier = ChatRecoveryResultApplier(controller: self)
    @ObservationIgnored
    lazy var recoveryMaintenanceCoordinator = ChatRecoveryMaintenanceCoordinator(controller: self)
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

        self.services = ChatControllerServices(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            requestBuilder: resolvedRequestBuilder,
            responseParser: resolvedResponseParser,
            transport: transport,
            openAIService: resolvedOpenAIService,
            fileDownloadService: fileDownloadService,
            serviceFactory: resolvedServiceFactory
        )
        self.didCompleteLaunchBootstrap = !bootstrapPolicy.runLaunchTasks
        conversationCoordinator.loadDefaultsFromSettings()
        if bootstrapPolicy.restoreLastConversation {
            conversationCoordinator.restoreLastConversationIfAvailable()
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

    func syncConversationProjection() {}

    func stopGeneration(savePartial: Bool = true) {
        sessionCoordinator.stopGeneration(savePartial: savePartial)
    }

    func suspendActiveSessionsForAppBackground() {
        sessionCoordinator.suspendActiveSessionsForAppBackground()
    }

    func cancelGeneratedFilePrefetches(_ requests: some Sequence<GeneratedFilePrefetchRequest>) {
        Task {
            for request in requests {
                await fileDownloadService.cancelGeneratedFilePrefetch(
                    fileId: request.fileID,
                    containerId: request.containerID
                )
            }
        }
    }
}
