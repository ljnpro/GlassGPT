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
    let hapticService = HapticService()
    @ObservationIgnored
    lazy var conversationCoordinator = AgentConversationCoordinator(state: self)
    @ObservationIgnored
    lazy var runCoordinator = AgentRunCoordinator(state: self)
    @ObservationIgnored
    let sessionRegistry = AgentSessionRegistry()

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
        conversationCoordinator.loadDefaultsFromSettings()
    }

    deinit {
        let sessionRegistry = sessionRegistry
        Task { @MainActor in
            sessionRegistry.removeAll()
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
        cancelVisibleRun()
        errorMessage = "Agent run stopped."
    }

    /// Cancels the run for the currently visible Agent conversation, if one exists.
    package func cancelVisibleRun() {
        guard let conversationID = currentConversation?.id,
              let execution = sessionRegistry.execution(for: conversationID)
        else {
            return
        }

        execution.task?.cancel()
        execution.service.cancelStream()
    }

    /// The reasoning effort levels available for Agent leader and worker configuration.
    package var availableReasoningEfforts: [ReasoningEffort] {
        ModelType.gpt5_4.availableEfforts
    }

    /// Human-readable summary of the current Agent runtime configuration.
    package var configurationSummary: String {
        var parts = [
            "Leader \(leaderReasoningEffort.displayName)",
            "Workers \(workerReasoningEffort.displayName)"
        ]
        if backgroundModeEnabled {
            parts.append("Background")
        }
        if flexModeEnabled {
            parts.append("Flex")
        }
        return parts.joined(separator: " · ")
    }

    /// Compact top-bar summary of the current Agent runtime configuration.
    package var compactConfigurationSummary: String {
        "L \(shortLabel(for: leaderReasoningEffort)) · W \(shortLabel(for: workerReasoningEffort))"
    }

    /// The persisted configuration bound to the currently visible Agent conversation.
    package var currentConfiguration: AgentConversationConfiguration {
        conversationCoordinator.currentConversationConfiguration
    }

    /// Applies a new Agent configuration to the currently visible conversation.
    package func applyConfiguration(_ configuration: AgentConversationConfiguration) {
        conversationCoordinator.applyConversationConfiguration(configuration)
    }

    /// Indicates whether the given Agent conversation currently has a live execution session.
    package func isConversationRunning(_ conversationID: UUID?) -> Bool {
        guard let conversationID else { return false }
        return sessionRegistry.execution(for: conversationID) != nil
    }

    /// Seeds a detached execution session for UI-test and recovery scenarios.
    package func seedDetachedExecution(
        for conversation: Conversation,
        draftMessageID: UUID,
        latestUserMessageID: UUID,
        snapshot: AgentRunSnapshot,
        apiKey: String = "sk-ui-test"
    ) {
        let execution = AgentExecutionState(
            conversationID: conversation.id,
            draftMessageID: draftMessageID,
            latestUserMessageID: latestUserMessageID,
            apiKey: apiKey,
            service: serviceFactory(),
            snapshot: snapshot
        )
        sessionRegistry.register(execution, visible: false)
    }

    var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }

    private func shortLabel(for effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            "Off"
        case .low:
            "Low"
        case .medium:
            "Med"
        case .high:
            "High"
        case .xhigh:
            "Max"
        }
    }
}
