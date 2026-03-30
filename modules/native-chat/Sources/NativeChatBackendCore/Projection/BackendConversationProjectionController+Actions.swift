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
        let hasAttachments = selectedImageData != nil || !pendingAttachments.isEmpty
        guard !trimmedText.isEmpty || hasAttachments else {
            return false
        }
        guard sessionStore.isSignedIn else {
            errorMessage = signInRequiredMessage
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

            // Upload pending file attachments to OpenAI via backend proxy
            var uploadedFileIds: [String] = []
            for i in pendingAttachments.indices {
                var attachment = pendingAttachments[i]
                guard let data = attachment.localData else { continue }
                attachment.uploadStatus = .uploading
                pendingAttachments[i] = attachment
                do {
                    let fileId = try await client.uploadFile(
                        data: data,
                        filename: attachment.filename,
                        mimeType: mimeTypeForExtension(attachment.fileType)
                    )
                    attachment.fileId = fileId
                    attachment.uploadStatus = .uploaded
                    pendingAttachments[i] = attachment
                    uploadedFileIds.append(fileId)
                } catch {
                    attachment.uploadStatus = .failed
                    pendingAttachments[i] = attachment
                    errorMessage = "File upload failed: \(attachment.filename)"
                    isRunActive = false
                    return
                }
            }

            let imageBase64 = selectedImageData?.base64EncodedString()
            let fileIds: [String]? = uploadedFileIds.isEmpty ? nil : uploadedFileIds

            let run = try await startConversationRun(
                text: text,
                conversationServerID: serverID,
                imageBase64: imageBase64,
                fileIds: fileIds
            )
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

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": "application/pdf"
        case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": "application/msword"
        case "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": "application/vnd.ms-powerpoint"
        case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": "application/vnd.ms-excel"
        case "csv": "text/csv"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        default: "application/octet-stream"
        }
    }
}
