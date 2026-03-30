import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import Observation

@Observable
@MainActor
package final class BackendAgentController {
    package var messages: [BackendMessageSurface] = []
    package var currentConversationID: UUID?
    package var currentStreamingText = ""
    package var currentThinkingText = ""
    package var activeToolCalls: [ToolCallInfo] = []
    package var liveCitations: [URLCitation] = []
    package var liveFilePathAnnotations: [FilePathAnnotation] = []
    package var errorMessage: String?
    package var selectedImageData: Data?
    package var pendingAttachments: [FileAttachment] = []
    package var leaderReasoningEffort: ReasoningEffort
    package var workerReasoningEffort: ReasoningEffort
    package var serviceTier: ServiceTier
    package var isRunning = false
    package var isThinking = false
    package var processSnapshot = AgentProcessSnapshot()

    @ObservationIgnored
    package let client: any BackendRequesting
    @ObservationIgnored
    package let loader: BackendConversationLoader
    @ObservationIgnored
    package let sessionStore: BackendSessionStore
    @ObservationIgnored
    package let settingsStore: SettingsStore
    @ObservationIgnored
    package var currentConversationRecord: Conversation?
    @ObservationIgnored
    package var runPollingTask: Task<Void, Never>?
    @ObservationIgnored
    package var submissionTask: Task<Void, Never>?

    @ObservationIgnored
    package var activeRunID: String?
    @ObservationIgnored
    package var lastStreamEventID: String?
    @ObservationIgnored
    package var lastRunSummary: RunSummaryDTO?
    @ObservationIgnored
    package var visibleSelectionToken = UUID()
    @ObservationIgnored
    package var skipAutomaticBootstrap = false
    @ObservationIgnored
    package var presentsSelectorOnLaunch = false
    @ObservationIgnored
    package var toolCallFirstSeen: [String: Date] = [:]
    @ObservationIgnored
    package var toolCallGracePeriodSeconds: TimeInterval = 3

    /// Creates the backend-owned agent projection controller for one account-scoped shell.
    package init(
        client: any BackendRequesting,
        loader: BackendConversationLoader,
        sessionStore: BackendSessionStore,
        settingsStore: SettingsStore
    ) {
        self.client = client
        self.loader = loader
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore

        let defaults = settingsStore.defaultAgentConversationConfiguration
        leaderReasoningEffort = defaults.leaderReasoningEffort
        workerReasoningEffort = defaults.workerReasoningEffort
        serviceTier = defaults.serviceTier
    }

    deinit {
        runPollingTask?.cancel()
        submissionTask?.cancel()
    }

    package var emptyStateDescription: String {
        sessionStore.isSignedIn
            ? "Leader planning, worker execution, and synthesis now continue on the backend."
            : "Sign in with Apple in Settings to enable synced agent runs."
    }

    package var configurationSummary: String {
        var parts = [
            "Leader \(leaderReasoningEffort.displayName)",
            "Workers \(workerReasoningEffort.displayName)"
        ]
        if flexModeEnabled {
            parts.append("Flex")
        }
        return parts.joined(separator: " · ")
    }

    package var compactConfigurationSummary: String {
        let leader = BackendConversationSupport.shortLabel(for: leaderReasoningEffort)
        let worker = BackendConversationSupport.shortLabel(for: workerReasoningEffort)
        return "L \(leader) · W \(worker)"
    }

    package var selectorStatusIcons: [String] {
        flexModeEnabled ? ["leaf.fill"] : []
    }

    package var shouldShowDetachedLiveSummaryCard: Bool {
        guard liveDraftMessageID == nil else {
            return false
        }
        return isRunning
    }
}
