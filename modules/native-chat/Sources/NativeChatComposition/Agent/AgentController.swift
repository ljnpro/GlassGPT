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
    /// Whether any Agent turn work is currently active.
    package var isRunning = false
    /// Whether the visible leader synthesis is currently streaming.
    package var isStreaming = false
    /// Whether the visible leader synthesis is currently emitting reasoning content.
    package var isThinking = false
    /// The current visible stage of the Agent council pipeline.
    package var currentStage: AgentStage?
    /// The per-worker progress pills shown during hidden worker stages.
    package var workerProgress = AgentWorkerProgress.defaultProgress

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
    let hapticService = HapticService()
    @ObservationIgnored
    var activeRunTask: Task<Void, Never>?
    @ObservationIgnored
    var visibleStreamService: OpenAIService?
    @ObservationIgnored
    lazy var conversationCoordinator = AgentConversationCoordinator(state: self)
    @ObservationIgnored
    lazy var runCoordinator = AgentRunCoordinator(state: self)

    /// Creates an Agent controller with persistence, transport, and service dependencies for council orchestration.
    package init(
        modelContext: ModelContext,
        settingsStore: SettingsStore,
        apiKeyStore: PersistedAPIKeyStore,
        requestBuilder: OpenAIRequestBuilder,
        responseParser: OpenAIResponseParser,
        transport: OpenAIDataTransport,
        serviceFactory: @escaping @MainActor () -> OpenAIService
    ) {
        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.requestBuilder = requestBuilder
        self.responseParser = responseParser
        self.transport = transport
        conversationRepository = ConversationRepository(modelContext: modelContext)
        self.serviceFactory = serviceFactory
    }

    deinit {
        let activeRunTask = activeRunTask
        let visibleStreamService = visibleStreamService
        Task { @MainActor in
            activeRunTask?.cancel()
            visibleStreamService?.cancelStream()
        }
    }

    /// Whether haptic feedback is enabled for Agent interactions.
    package var hapticsEnabled: Bool {
        settingsStore.hapticEnabled
    }

    /// Starts a new Agent turn from the provided user text and returns whether the turn began successfully.
    @discardableResult
    package func sendMessage(text: String) -> Bool {
        do {
            let prepared = try conversationCoordinator.prepareNewTurn(text: text)
            runCoordinator.startTurn(prepared)
            return true
        } catch AgentPreparationError.alreadyRunning {
            return false
        } catch AgentPreparationError.emptyInput {
            return false
        } catch AgentPreparationError.missingAPIKey {
            errorMessage = "Please add your OpenAI API key in Settings."
            return false
        } catch {
            errorMessage = "Failed to start the Agent run."
            return false
        }
    }

    /// Retries the latest Agent turn when a retryable user message is available.
    package func retryLastTurn() {
        do {
            let prepared = try conversationCoordinator.prepareRetryTurn()
            runCoordinator.startTurn(prepared)
        } catch AgentPreparationError.missingAPIKey {
            errorMessage = "Please add your OpenAI API key in Settings."
        } catch {
            errorMessage = "Nothing is available to retry."
        }
    }

    /// Clears the visible Agent state and starts a fresh empty conversation surface.
    package func startNewConversation() {
        conversationCoordinator.startNewConversation()
    }

    /// Loads an existing persisted Agent conversation into the visible surface.
    package func loadConversation(_ conversation: Conversation) {
        conversationCoordinator.loadConversation(conversation)
    }

    /// Stops the active Agent run and surfaces a user-visible stopped state.
    package func stopGeneration() {
        cancelActiveRun()
        errorMessage = "Agent run stopped."
    }

    /// Cancels any active hidden or visible Agent work without resetting the loaded conversation.
    package func cancelActiveRun() {
        activeRunTask?.cancel()
        activeRunTask = nil
        visibleStreamService?.cancelStream()
        visibleStreamService = nil
    }
}
