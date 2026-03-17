import Foundation

@MainActor
final class StreamingCoordinator {
    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    unowned let viewModel: ChatViewModel
    let recoveryCoordinator: RecoveryCoordinator

    init(
        viewModel: ChatViewModel,
        recoveryCoordinator: RecoveryCoordinator
    ) {
        self.viewModel = viewModel
        self.recoveryCoordinator = recoveryCoordinator
    }

    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        guard !viewModel.isStreaming else { return false }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || viewModel.selectedImageData != nil || !viewModel.pendingAttachments.isEmpty else { return false }
        guard !viewModel.apiKey.isEmpty else {
            viewModel.errorMessage = "Please add your OpenAI API key in Settings."
            return false
        }

        let imageDataToSend = viewModel.selectedImageData
        let attachmentsToSend = viewModel.pendingAttachments

        let userMessage = Message(role: .user, content: text, imageData: imageDataToSend)
        if !attachmentsToSend.isEmpty {
            viewModel.messagePersistence.setFileAttachments(attachmentsToSend, on: userMessage)
        }

        if viewModel.currentConversation == nil {
            viewModel.currentConversation = viewModel.conversationRepository.createConversation(
                configuration: viewModel.conversationConfiguration
            )
        }

        userMessage.conversation = viewModel.currentConversation
        viewModel.currentConversation?.messages.append(userMessage)
        viewModel.currentConversation?.model = viewModel.selectedModel.rawValue
        viewModel.currentConversation?.reasoningEffort = viewModel.reasoningEffort.rawValue
        viewModel.currentConversation?.backgroundModeEnabled = viewModel.backgroundModeEnabled
        viewModel.currentConversation?.serviceTierRawValue = viewModel.serviceTier.rawValue
        viewModel.currentConversation?.updatedAt = .now
        viewModel.messages.append(userMessage)

        guard viewModel.saveContext(reportingUserError: "Failed to save your message.", logContext: "sendMessage.userMessage") else {
            return false
        }

        viewModel.selectedImageData = nil
        viewModel.pendingAttachments = []
        viewModel.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: viewModel.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = viewModel.currentConversation
        viewModel.currentConversation?.messages.append(draft)
        viewModel.saveContextIfPossible("sendMessage.draft")

        guard let session = viewModel.makeStreamingSession(for: draft) else {
            viewModel.errorMessage = "Failed to start response session."
            return false
        }

        viewModel.registerSession(session, visible: true)
        session.beginSubmitting()
        viewModel.syncVisibleState(from: session)

        HapticService.shared.impact(.light)

        if !attachmentsToSend.isEmpty {
            Task { @MainActor in
                let uploadedAttachments = await self.viewModel.uploadAttachments(attachmentsToSend)
                self.viewModel.messagePersistence.setFileAttachments(uploadedAttachments, on: userMessage)
                self.viewModel.saveContextIfPossible("sendMessage.uploadedAttachments")
                self.startStreamingRequest(for: session)
            }
        } else {
            startStreamingRequest(for: session)
        }

        return true
    }

    func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = viewModel.currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    func startStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.requestMessages else { return }

        let requestAPIKey = viewModel.apiKey
        let streamID = UUID()
        session.beginStreaming(streamID: streamID)
        viewModel.setRecoveryPhase(.idle, for: session)
        viewModel.syncVisibleState(from: session)

        session.task?.cancel()
        session.task = Task { @MainActor in
            let stream = session.service.streamChat(
                apiKey: requestAPIKey,
                messages: requestMessages,
                model: session.requestModel,
                reasoningEffort: session.requestEffort,
                backgroundModeEnabled: session.requestUsesBackgroundMode,
                serviceTier: session.requestServiceTier
            )

            var receivedConnectionLost = false
            var didReceiveCompletedEvent = false
            var pendingRecoveryResponseId: String?
            var pendingRecoveryError: String?

            for await event in stream {
                guard self.viewModel.isSessionActive(session), session.activeStreamID == streamID else { break }

                switch self.viewModel.applyStreamEvent(event, to: session, animated: self.viewModel.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    self.viewModel.finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    self.viewModel.saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                    } else if !session.currentText.isEmpty {
                        self.viewModel.finalizeSessionAsPartial(session)
                    } else if let message = self.viewModel.findMessage(byId: session.messageID) {
                        self.viewModel.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    self.viewModel.saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    self.viewModel.saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !session.currentText.isEmpty {
                        self.viewModel.finalizeSessionAsPartial(session)
                        if self.viewModel.visibleSessionMessageID == session.messageID {
                            self.viewModel.errorMessage = error.localizedDescription
                            HapticService.shared.notify(.error)
                        }
                    } else if let message = self.viewModel.findMessage(byId: session.messageID) {
                        self.viewModel.removeEmptyMessage(message, for: session)
                        if self.viewModel.visibleSessionMessageID == session.messageID {
                            self.viewModel.errorMessage = error.localizedDescription
                            self.viewModel.clearLiveGenerationState(clearDraft: true)
                            HapticService.shared.notify(.error)
                        }
                    }
                }
            }

            guard self.viewModel.isSessionActive(session), session.activeStreamID == streamID else {
                self.viewModel.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                self.viewModel.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                session.setRecoveryPhase(.checkingStatus)
                self.viewModel.setRecoveryPhase(.checkingStatus, for: session)
                if self.viewModel.visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    self.viewModel.errorMessage = pendingRecoveryError
                }
                self.viewModel.syncVisibleState(from: session)
                self.recoveryCoordinator.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.requestUsesBackgroundMode
                )
                self.viewModel.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = session.responseId {
                    session.setRecoveryPhase(.checkingStatus)
                    self.viewModel.setRecoveryPhase(.checkingStatus, for: session)
                    self.viewModel.syncVisibleState(from: session)
                    self.recoveryCoordinator.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                    self.viewModel.endBackgroundTask()
                    return
                }

                let nextAttempt = reconnectAttempt + 1
                if nextAttempt < Self.maxReconnectAttempts {
                    let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Retrying full stream in \(Double(delay) / 1_000_000_000)s")
                    #endif

                    do {
                        try await Task.sleep(nanoseconds: delay)
                    } catch {
                        self.viewModel.endBackgroundTask()
                        return
                    }

                    guard self.viewModel.isSessionActive(session), session.activeStreamID == streamID else {
                        self.viewModel.endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    self.startStreamingRequest(for: session, reconnectAttempt: nextAttempt)
                    self.viewModel.endBackgroundTask()
                    return
                }

                if !session.currentText.isEmpty {
                    self.viewModel.finalizeSessionAsPartial(session)
                } else if let message = self.viewModel.findMessage(byId: session.messageID) {
                    self.viewModel.removeEmptyMessage(message, for: session)
                    if self.viewModel.visibleSessionMessageID == session.messageID {
                        self.viewModel.errorMessage = "Connection lost. Please check your network and try again."
                        self.viewModel.clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }

                self.viewModel.endBackgroundTask()
                return
            }

            if session.isStreaming {
                if let responseId = session.responseId {
                    self.viewModel.saveSessionNow(session)
                    session.setRecoveryPhase(.checkingStatus)
                    self.viewModel.setRecoveryPhase(.checkingStatus, for: session)
                    self.viewModel.syncVisibleState(from: session)
                    self.recoveryCoordinator.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                } else if !session.currentText.isEmpty {
                    self.viewModel.finalizeSessionAsPartial(session)
                } else if let message = self.viewModel.findMessage(byId: session.messageID) {
                    self.viewModel.removeEmptyMessage(message, for: session)
                    if self.viewModel.visibleSessionMessageID == session.messageID {
                        self.viewModel.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            self.viewModel.endBackgroundTask()
        }
    }

    func persistToolCallsAndCitations() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.saveSessionNow(session)
    }

    func saveDraftIfNeeded() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.saveSessionIfNeeded(session)
    }

    func saveDraftNow() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.saveSessionNow(session)
    }

    func finalizeDraft() {
        guard let session = viewModel.currentVisibleSession else {
            viewModel.clearLiveGenerationState(clearDraft: true)
            viewModel.setVisibleRecoveryPhase(.idle)
            return
        }
        viewModel.finalizeSession(session)
    }

    func finalizeDraftAsPartial() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.finalizeSessionAsPartial(session)
    }

    func removeEmptyDraft() {
        guard let session = viewModel.currentVisibleSession, let draft = viewModel.draftMessage else { return }
        viewModel.removeEmptyMessage(draft, for: session)
    }

    func stopGeneration(savePartial: Bool = true) {
        guard let session = viewModel.currentVisibleSession else { return }

        let pendingBackgroundCancellation = ChatSessionDecisions.pendingBackgroundCancellation(
            requestUsesBackgroundMode: session.requestUsesBackgroundMode,
            responseId: session.responseId,
            messageId: session.messageID
        )

        session.cancelStreaming()
        session.service.cancelStream()
        session.task?.cancel()
        viewModel.errorMessage = nil

        if savePartial && !session.currentText.isEmpty {
            persistToolCallsAndCitations()
            viewModel.finalizeSession(session)
        } else if let draft = viewModel.findMessage(byId: session.messageID) {
            if !session.currentText.isEmpty {
                draft.content = session.currentText
            }
            if !session.currentThinking.isEmpty {
                draft.thinking = session.currentThinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                viewModel.saveContextIfPossible("stopGeneration.persistPartialDraft")
                viewModel.upsertMessage(draft)
                viewModel.removeSession(session)
            } else {
                viewModel.removeEmptyMessage(draft, for: session)
            }
        }

        viewModel.setVisibleRecoveryPhase(.idle)
        viewModel.endBackgroundTask()
        HapticService.shared.impact(.medium)

        if let pendingBackgroundCancellation {
            Task { @MainActor in
                await self.recoveryCoordinator.cancelBackgroundResponseAndSync(
                    responseId: pendingBackgroundCancellation.responseId,
                    messageId: pendingBackgroundCancellation.messageId
                )
            }
        }
    }
}
