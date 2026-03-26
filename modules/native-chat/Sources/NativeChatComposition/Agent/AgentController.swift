import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import OpenAITransport
import SwiftData
import SwiftUI

/// Observable controller driving the dedicated Agent mode.
@Observable
@MainActor
package final class AgentController {
    /// The visible transcript messages for the active Agent conversation.
    package var messages: [Message] = []
    /// The currently selected Agent conversation, if any.
    package var currentConversation: Conversation?
    /// The live assistant draft message while the leader synthesis is streaming.
    package var draftMessage: Message?
    /// The streamed visible assistant text for the current draft.
    package var currentStreamingText = ""
    /// The streamed reasoning text for the current draft.
    package var currentThinkingText = ""
    /// The currently active tool calls during the visible leader synthesis.
    package var activeToolCalls: [ToolCallInfo] = []
    /// Live URL citations emitted by the visible leader synthesis.
    package var liveCitations: [URLCitation] = []
    /// Live file annotations emitted by the visible leader synthesis.
    package var liveFilePathAnnotations: [FilePathAnnotation] = []
    /// The user-facing error banner text, if the current run failed.
    package var errorMessage: String?
    /// Pending image attachment for the Agent composer.
    package var selectedImageData: Data?
    /// Pending file attachments for the Agent composer.
    package var pendingAttachments: [FileAttachment] = []
    /// The selected leader reasoning effort for the visible Agent conversation.
    package var leaderReasoningEffort: ReasoningEffort = .high
    /// The shared worker reasoning effort for the visible Agent conversation.
    package var workerReasoningEffort: ReasoningEffort = .low
    /// Whether background mode is enabled for the visible Agent conversation.
    package var backgroundModeEnabled = false
    /// The selected service tier for the visible Agent conversation.
    package var serviceTier: ServiceTier = .standard
    /// Whether any Agent turn work is currently active.
    package var isRunning = false
    /// Whether the visible leader synthesis is currently streaming.
    package var isStreaming = false
    /// Whether the visible leader synthesis is currently emitting reasoning content.
    package var isThinking = false
    /// The current visible stage of the Agent council pipeline.
    package var currentStage: AgentStage?
    /// The latest leader brief summary for the active run, if available.
    package var leaderBriefSummary: String?
    /// Projected dynamic process state for the current live run.
    package var processSnapshot = AgentProcessSnapshot()
    /// The per-worker progress pills for the first worker round.
    package var workersRoundOneProgress = AgentWorkerProgress.defaultProgress
    /// The per-worker progress pills for cross-review.
    package var crossReviewProgress = AgentWorkerProgress.defaultProgress

    @ObservationIgnored
    let modelContext: ModelContext
    @ObservationIgnored
    let settingsStore: SettingsStore
    @ObservationIgnored
    let apiKeyStore: PersistedAPIKeyStore
    @ObservationIgnored
    let requestBuilder: OpenAIRequestBuilder
    @ObservationIgnored
    let responseParser: OpenAIResponseParser
    @ObservationIgnored
    let transport: OpenAIDataTransport
    @ObservationIgnored
    let conversationRepository: ConversationRepository
    @ObservationIgnored
    let serviceFactory: @MainActor () -> OpenAIService
    @ObservationIgnored
    let backgroundTaskCoordinator: BackgroundTaskCoordinator
    /// Tracks whether launch bootstrap tasks already ran for the current process.
    package var didCompleteLaunchBootstrap = false

    @ObservationIgnored
    let hapticService = HapticService()
    @ObservationIgnored
    lazy var conversationCoordinator = AgentConversationCoordinator(state: self)
    @ObservationIgnored
    lazy var runCoordinator = AgentRunCoordinator(state: self)
    @ObservationIgnored
    lazy var planningEngine = AgentPlanningEngine(state: self)
    @ObservationIgnored
    lazy var workerRuntime = AgentWorkerRuntime(state: self)
    @ObservationIgnored
    let sessionRegistry = AgentSessionRegistry()
    @ObservationIgnored
    lazy var lifecycleCoordinator = AgentLifecycleCoordinator(state: self)

    /// Creates an Agent controller with persistence, transport, and service dependencies for council orchestration.
    package init(
        modelContext: ModelContext,
        settingsStore: SettingsStore,
        apiKeyStore: PersistedAPIKeyStore,
        requestBuilder: OpenAIRequestBuilder,
        responseParser: OpenAIResponseParser,
        transport: OpenAIDataTransport,
        serviceFactory: @escaping @MainActor () -> OpenAIService,
        bootstrapPolicy: FeatureBootstrapPolicy = .live
    ) {
        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.requestBuilder = requestBuilder
        self.responseParser = responseParser
        self.transport = transport
        conversationRepository = ConversationRepository(modelContext: modelContext)
        self.serviceFactory = serviceFactory
        backgroundTaskCoordinator = BackgroundTaskCoordinator()
        didCompleteLaunchBootstrap = !bootstrapPolicy.runLaunchTasks
        conversationCoordinator.loadDefaultsFromSettings()
        if bootstrapPolicy.restoreLastConversation {
            conversationCoordinator.restoreLastConversationIfAvailable()
        }
        if bootstrapPolicy.setupLifecycleObservers {
            lifecycleCoordinator.setupLifecycleObservers()
        }
        if bootstrapPolicy.runLaunchTasks {
            Task { @MainActor [weak self] in
                guard let self else { return }
                didCompleteLaunchBootstrap = true
                await lifecycleCoordinator.handleLaunchBootstrap()
            }
        }
    }

    deinit {
        let backgroundTaskCoordinator = backgroundTaskCoordinator
        let sessionRegistry = sessionRegistry
        Task { @MainActor in
            backgroundTaskCoordinator.endBackgroundTask()
            sessionRegistry.removeAll()
        }
    }

    /// Whether haptic feedback is enabled for Agent interactions.
    package var hapticsEnabled: Bool {
        settingsStore.hapticEnabled
    }
}
