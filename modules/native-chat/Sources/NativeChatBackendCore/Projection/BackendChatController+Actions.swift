import ChatDomain
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation

@MainActor
package extension BackendChatController {
    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }
        guard sessionStore.isSignedIn else {
            errorMessage = "Sign in with Apple in Settings to use chat."
            return false
        }
        guard selectedImageData == nil, pendingAttachments.isEmpty else {
            errorMessage = "Attachments are not available in Beta 5.0 yet."
            return false
        }
        guard !isStreaming else {
            return false
        }

        errorMessage = nil
        isStreaming = true
        currentThinkingText = ""
        currentStreamingText = ""
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
            isStreaming = false
            return
        }

        runPollingTask?.cancel()
        runPollingTask = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await client.cancelRun(activeRunID)
                try await refreshVisibleConversation()
            } catch {
                errorMessage = error.localizedDescription
            }
            self.activeRunID = nil
            isStreaming = false
            isThinking = false
        }
    }

    func startNewConversation() {
        submissionTask?.cancel()
        runPollingTask?.cancel()
        runPollingTask = nil
        submissionTask = nil
        activeRunID = nil
        setCurrentConversation(nil)
        visibleSelectionToken = UUID()
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isStreaming = false
        isThinking = false
        errorMessage = nil
        selectedImageData = nil
        pendingAttachments.removeAll()
    }

    func loadConversation(serverID: String) {
        submissionTask?.cancel()
        runPollingTask?.cancel()
        runPollingTask = nil
        activeRunID = nil
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        isStreaming = false
        isThinking = false
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
                syncMessages()
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

    private func submitMessage(_ text: String, selectionToken: UUID) async {
        defer { submissionTask = nil }

        do {
            let conversation = try await ensureConversation()
            guard visibleSelectionToken == selectionToken else {
                return
            }

            let serverID = try requireConversationServerID(for: conversation)
            let run = try await client.sendMessage(text, to: serverID)
            guard visibleSelectionToken == selectionToken else {
                return
            }
            activeRunID = run.id
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
            isStreaming = false
            isThinking = false
        }
    }

    private func ensureConversation() async throws -> Conversation {
        if let currentConversationRecordValue {
            return currentConversationRecordValue
        }

        let createdConversation = try await loader.createConversation(
            title: BackendConversationSupport.defaultConversationTitle(for: .chat),
            mode: .chat
        )
        setCurrentConversation(createdConversation)
        hydrateConfigurationFromConversation()
        syncMessages()
        return createdConversation
    }

    private func requireConversationServerID(for conversation: Conversation) throws -> String {
        if let serverID = conversation.serverID, !serverID.isEmpty {
            return serverID
        }
        throw BackendConversationLoaderError.missingConversationIdentifier
    }
}
