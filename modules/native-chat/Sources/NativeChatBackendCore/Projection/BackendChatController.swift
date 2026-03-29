import BackendAuth
import BackendClient
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import Observation

@Observable
@MainActor
package final class BackendChatController {
    package var messages: [BackendMessageSurface] = []
    package var currentConversationID: UUID?
    package var currentStreamingText = ""
    package var currentThinkingText = ""
    package var activeToolCalls: [ToolCallInfo] = []
    package var liveCitations: [URLCitation] = []
    package var liveFilePathAnnotations: [FilePathAnnotation] = []
    package var isStreaming = false
    package var isThinking = false
    package var errorMessage: String?
    package var selectedImageData: Data?
    package var pendingAttachments: [FileAttachment] = []
    package var selectedModel: ModelType
    package var reasoningEffort: ReasoningEffort
    package var serviceTier: ServiceTier

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
    package var visibleSelectionToken = UUID()
    @ObservationIgnored
    package var skipAutomaticBootstrap = false
    @ObservationIgnored
    package var presentsSelectorOnLaunch = false

    /// Creates the backend-owned chat projection controller for one account-scoped shell.
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

        let defaults = settingsStore.defaultConversationConfiguration
        selectedModel = defaults.model
        reasoningEffort = defaults.reasoningEffort
        serviceTier = defaults.serviceTier
    }

    deinit {
        runPollingTask?.cancel()
        submissionTask?.cancel()
    }

    package var emptyStateDescription: String {
        sessionStore.isSignedIn
            ? "Your conversations now sync through the backend."
            : "Sign in with Apple in Settings to enable synced chat."
    }

    package var configurationSummary: String {
        if reasoningEffort == .none {
            selectedModel.displayName
        } else {
            "\(selectedModel.displayName) · \(reasoningEffort.displayName)"
        }
    }

    package var selectorStatusIcons: [String] {
        var icons: [String] = []
        if proModeEnabled {
            icons.append("brain")
        }
        if flexModeEnabled {
            icons.append("leaf.fill")
        }
        return icons
    }

    package var proModeEnabled: Bool {
        get { selectedModel == .gpt5_4_pro }
        set {
            selectedModel = newValue ? .gpt5_4_pro : .gpt5_4
            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }
            persistVisibleConfiguration()
        }
    }
}
