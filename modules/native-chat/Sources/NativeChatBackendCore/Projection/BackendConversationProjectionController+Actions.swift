import BackendAuth
import ChatDomain
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

@MainActor
package extension BackendConversationProjectionController {
    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }
        guard sessionStore.isSignedIn else {
            errorMessage = signInRequiredMessage
            return false
        }
        guard selectedImageData == nil, pendingAttachments.isEmpty else {
            errorMessage = "Attachments are not available in 5.3.0 yet."
            return false
        }
        guard !isRunActive else {
            return false
        }

        errorMessage = nil
        prepareForMessageSubmission()
        let selectionToken = visibleSelectionToken
        submissionTask?.cancel()
        submissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await submitVisibleMessage(trimmedText, selectionToken: selectionToken)
        }
        return true
    }

    func stopGeneration() {
        guard let activeRunID else {
            isRunActive = false
            isThinking = false
            return
        }

        runPollingTask?.cancel()
        runPollingTask = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let run = try await client.cancelRun(activeRunID)
                applyCancelledRun(run)
                try await refreshVisibleConversation()
            } catch {
                errorMessage = error.localizedDescription
            }
            self.activeRunID = nil
            lastStreamEventID = nil
            isRunActive = false
            isThinking = false
        }
    }

    func startNewConversation() {
        submissionTask?.cancel()
        runPollingTask?.cancel()
        runPollingTask = nil
        submissionTask = nil
        activeRunID = nil
        lastStreamEventID = nil
        setCurrentConversation(nil)
        visibleSelectionToken = UUID()
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isRunActive = false
        isThinking = false
        resetModeSpecificState()
        errorMessage = nil
        selectedImageData = nil
        pendingAttachments.removeAll()
    }

    func loadConversation(serverID: String) {
        submissionTask?.cancel()
        runPollingTask?.cancel()
        runPollingTask = nil
        activeRunID = nil
        lastStreamEventID = nil
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isRunActive = false
        isThinking = false
        resetModeSpecificState()
        let selectionToken = UUID()
        visibleSelectionToken = selectionToken

        loadCachedConversationIfAvailable(serverID: serverID)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let conversation = try await loader.refreshConversationDetail(serverID: serverID)
                guard visibleSelectionToken == selectionToken else {
                    return
                }
                guard applyLoadedConversation(conversation) else {
                    return
                }
                hydrateConfigurationFromConversation()
                syncVisibleState()
                await restoreActiveRunIfNeeded(selectionToken: selectionToken)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handlePickedDocuments(_ urls: [URL]) {
        pendingAttachments.append(contentsOf: BackendConversationSupport.pendingAttachments(from: urls))
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func submitVisibleMessage(_ text: String, selectionToken: UUID) async {
        defer { submissionTask = nil }

        do {
            let conversation = try await ensureConversation()
            guard visibleSelectionToken == selectionToken else {
                return
            }

            let serverID = try requireConversationServerID(for: conversation)
            persistVisibleConfiguration()
            try await syncVisibleConfigurationToBackendIfNeeded()
            let run = try await startConversationRun(text: text, conversationServerID: serverID)
            guard visibleSelectionToken == selectionToken else {
                return
            }
            activeRunID = run.id
            applyStartedRun(run)
            selectedImageData = nil
            pendingAttachments.removeAll()
            try await refreshVisibleConversation()
            startRunPolling(
                conversationServerID: serverID,
                runID: run.id,
                selectionToken: selectionToken
            )
        } catch {
            errorMessage = error.localizedDescription
            isRunActive = false
            isThinking = false
        }
    }
}
