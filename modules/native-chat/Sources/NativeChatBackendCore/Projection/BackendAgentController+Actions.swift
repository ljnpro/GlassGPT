import ChatDomain
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

@MainActor
package extension BackendAgentController {
    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }
        guard sessionStore.isSignedIn else {
            errorMessage = "Sign in with Apple in Settings to use Agent mode."
            return false
        }
        guard selectedImageData == nil, pendingAttachments.isEmpty else {
            errorMessage = "Attachments are not available in Beta 5.0 yet."
            return false
        }
        guard !isRunning else {
            return false
        }

        errorMessage = nil
        isRunning = true
        isThinking = true
        currentThinkingText = ""
        currentStreamingText = ""
        processSnapshot = AgentProcessSnapshot(
            activity: .triage,
            leaderLiveStatus: "Queued",
            leaderLiveSummary: "Preparing agent run"
        )
        let selectionToken = visibleSelectionToken
        submissionTask?.cancel()
        submissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await submitMessage(trimmedText, selectionToken: selectionToken)
        }
        return true
    }

    func stopGeneration() {
        guard let activeRunID else {
            isRunning = false
            isThinking = false
            return
        }

        runPollingTask?.cancel()
        runPollingTask = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                lastRunSummary = try await client.cancelRun(activeRunID)
                processSnapshot = BackendConversationSupport.processSnapshot(
                    for: lastRunSummary,
                    progressLabel: "Cancelled"
                )
                try await refreshVisibleConversation()
            } catch {
                errorMessage = error.localizedDescription
            }
            self.activeRunID = nil
            isRunning = false
            isThinking = false
        }
    }

    func startNewConversation() {
        submissionTask?.cancel()
        runPollingTask?.cancel()
        runPollingTask = nil
        submissionTask = nil
        activeRunID = nil
        lastRunSummary = nil
        setCurrentConversation(nil)
        visibleSelectionToken = UUID()
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isRunning = false
        isThinking = false
        processSnapshot = AgentProcessSnapshot()
        errorMessage = nil
        selectedImageData = nil
        pendingAttachments.removeAll()
    }

    func loadConversation(serverID: String) {
        submissionTask?.cancel()
        runPollingTask?.cancel()
        runPollingTask = nil
        activeRunID = nil
        lastRunSummary = nil
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

    private func submitMessage(_ text: String, selectionToken: UUID) async {
        defer { submissionTask = nil }

        do {
            let conversation = try await ensureConversation()
            guard visibleSelectionToken == selectionToken else {
                return
            }

            let serverID = try requireConversationServerID(for: conversation)
            let run = try await client.startAgentRun(prompt: text, in: serverID)
            guard visibleSelectionToken == selectionToken else {
                return
            }
            activeRunID = run.id
            lastRunSummary = run
            processSnapshot = BackendConversationSupport.processSnapshot(
                for: run,
                progressLabel: run.visibleSummary
            )
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
            isRunning = false
            isThinking = false
        }
    }

    private func ensureConversation() async throws -> Conversation {
        if let currentConversationRecordValue {
            return currentConversationRecordValue
        }

        let createdConversation = try await loader.createConversation(
            title: BackendConversationSupport.defaultConversationTitle(for: .agent),
            mode: .agent
        )
        setCurrentConversation(createdConversation)
        hydrateConfigurationFromConversation()
        syncVisibleState()
        return createdConversation
    }

    private func requireConversationServerID(for conversation: Conversation) throws -> String {
        if let serverID = conversation.serverID, !serverID.isEmpty {
            return serverID
        }
        throw BackendConversationLoaderError.missingConversationIdentifier
    }
}
