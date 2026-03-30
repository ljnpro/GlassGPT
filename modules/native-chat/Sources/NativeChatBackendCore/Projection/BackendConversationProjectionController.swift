import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

/// Shared control surface required by backend conversation projection controllers.
@MainActor
package protocol BackendConversationProjectionController: AnyObject {
    var messages: [BackendMessageSurface] { get set }
    var currentConversationID: UUID? { get set }
    var currentStreamingText: String { get set }
    var currentThinkingText: String { get set }
    var activeToolCalls: [ToolCallInfo] { get set }
    var liveCitations: [URLCitation] { get set }
    var liveFilePathAnnotations: [FilePathAnnotation] { get set }
    var errorMessage: String? { get set }
    var selectedImageData: Data? { get set }
    var pendingAttachments: [FileAttachment] { get set }
    var currentConversationRecord: Conversation? { get set }
    var runPollingTask: Task<Void, Never>? { get set }
    var submissionTask: Task<Void, Never>? { get set }
    var activeRunID: String? { get set }
    var lastStreamEventID: String? { get set }
    var visibleSelectionToken: UUID { get set }

    var client: any BackendRequesting { get }
    var loader: BackendConversationLoader { get }
    var sessionStore: BackendSessionStore { get }

    var conversationMode: ConversationMode { get }
    var isRunActive: Bool { get set }
    var isThinking: Bool { get set }
    var sessionAccountID: String? { get }
    var signInRequiredMessage: String { get }
    var supportsAttachments: Bool { get }

    func applyStartedRun(_ run: RunSummaryDTO)
    func applyCancelledRun(_ run: RunSummaryDTO?)
    func applyRestoredRunSummary(_ run: RunSummaryDTO)
    func ensureConversation() async throws -> Conversation
    func hydrateConfigurationFromConversation()
    func persistVisibleConfiguration()
    func prepareForMessageSubmission()
    func refreshVisibleConversation() async throws
    func requestUpdatedConversationConfiguration(serverID: String) async throws -> Conversation
    func resetModeSpecificState()
    func restoreActiveRunIfNeeded(selectionToken: UUID) async
    var toolCallFirstSeen: [String: Date] { get set }
    var toolCallGracePeriodSeconds: TimeInterval { get set }
    func startConversationRun(
        text: String,
        conversationServerID: String,
        imageBase64: String?,
        fileIds: [String]?
    ) async throws -> RunSummaryDTO
    func startRunPolling(conversationServerID: String, runID: String, selectionToken: UUID)
    func syncVisibleConfigurationToBackendIfNeeded() async throws
    func syncVisibleState()
}

@MainActor
package extension BackendConversationProjectionController {
    /// Default restored-run hook for controllers that do not need mode-specific restore state.
    func applyRestoredRunSummary(_: RunSummaryDTO) {}

    /// Default reset hook for controllers that do not need mode-specific reset state.
    func resetModeSpecificState() {}

    /// Clears shared live response state before submission starts.
    func prepareSharedMessageSubmission(startThinking: Bool = false) {
        isRunActive = true
        isThinking = startThinking
        currentThinkingText = ""
        currentStreamingText = ""
    }

    /// Default submission preparation for controllers without mode-specific setup.
    func prepareForMessageSubmission() {
        prepareSharedMessageSubmission()
    }

    var supportsAttachments: Bool {
        true
    }

    /// Stores the accepted run identifier in shared controller state.
    func applySharedStartedRun(_ run: RunSummaryDTO) {
        activeRunID = run.id
    }

    /// Default run-start hook for controllers without additional mode-specific state.
    func applyStartedRun(_ run: RunSummaryDTO) {
        applySharedStartedRun(run)
    }

    /// Default cancellation hook for controllers without additional mode-specific state.
    func applyCancelledRun(_: RunSummaryDTO?) {}

    /// Rebuilds visible transcript state from the current persisted conversation record.
    func syncVisibleState() {
        messages = BackendConversationSupport.sortedMessages(in: currentConversationRecord)
        currentConversationID = currentConversationRecord?.id
    }

    /// Pushes visible configuration changes to the backend when a server record exists.
    func syncVisibleConfigurationToBackendIfNeeded() async throws {
        guard let serverID = currentConversationRecord?.serverID else {
            return
        }
        currentConversationRecord = try await requestUpdatedConversationConfiguration(serverID: serverID)
        syncVisibleState()
    }

    /// Reloads the active conversation from the backend and rehydrates visible state.
    func refreshVisibleConversation() async throws {
        guard let serverID = currentConversationRecord?.serverID else {
            syncVisibleState()
            return
        }
        currentConversationRecord = try await loader.refreshConversationDetail(serverID: serverID)
        hydrateConfigurationFromConversation()
        syncVisibleState()
    }

    /// Restores an in-flight run after selection or bootstrap if the backend still reports it active.
    func restoreActiveRunIfNeeded(selectionToken: UUID) async {
        guard sessionStore.isSignedIn,
              let conversation = currentConversationRecord,
              let conversationServerID = conversation.serverID,
              let runID = conversation.lastRunServerID,
              visibleSelectionToken == selectionToken
        else {
            return
        }

        do {
            let run = try await client.fetchRun(runID)
            guard visibleSelectionToken == selectionToken else {
                return
            }

            applyRestoredRunSummary(run)
            let previousActiveRunID = activeRunID
            if run.status == .queued || run.status == .running {
                activeRunID = run.id
                isRunActive = true
                if runPollingTask == nil || previousActiveRunID != run.id {
                    startRunPolling(
                        conversationServerID: conversationServerID,
                        runID: run.id,
                        selectionToken: selectionToken
                    )
                }
            } else if activeRunID == run.id {
                activeRunID = nil
                isRunActive = false
                isThinking = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the initial conversation selection for the current authenticated account.
    func bootstrap() async {
        guard sessionStore.isSignedIn else {
            messages = []
            currentConversationRecord = nil
            currentConversationID = nil
            resetModeSpecificState()
            return
        }

        do {
            let conversations = try await loader.refreshConversationIndex(mode: conversationMode)
            if let currentConversationRecord,
               let reloaded = conversations.first(where: { $0.id == currentConversationRecord.id }) {
                self.currentConversationRecord = reloaded
                hydrateConfigurationFromConversation()
                syncVisibleState()
                try await refreshVisibleConversation()
                await restoreActiveRunIfNeeded(selectionToken: visibleSelectionToken)
            } else if let mostRecent = conversations.first {
                currentConversationRecord = mostRecent
                hydrateConfigurationFromConversation()
                syncVisibleState()
                try await refreshVisibleConversation()
                await restoreActiveRunIfNeeded(selectionToken: visibleSelectionToken)
            } else {
                startNewConversation()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
