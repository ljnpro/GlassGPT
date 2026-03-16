import Foundation

@MainActor
extension ChatViewModel {

    // MARK: - Send Message

    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        guard !isStreaming else { return false }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil || !pendingAttachments.isEmpty else { return false }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your OpenAI API key in Settings."
            return false
        }

        let imageDataToSend = selectedImageData
        let attachmentsToSend = pendingAttachments

        let userMessage = Message(
            role: .user,
            content: text,
            imageData: imageDataToSend
        )

        if !attachmentsToSend.isEmpty {
            userMessage.fileAttachmentsData = FileAttachment.encode(attachmentsToSend)
        }

        if currentConversation == nil {
            let conversation = conversationRepository.createConversation(configuration: conversationConfiguration)
            currentConversation = conversation
        }

        userMessage.conversation = currentConversation
        currentConversation?.messages.append(userMessage)
        currentConversation?.model = selectedModel.rawValue
        currentConversation?.reasoningEffort = reasoningEffort.rawValue
        currentConversation?.backgroundModeEnabled = backgroundModeEnabled
        currentConversation?.serviceTierRawValue = serviceTier.rawValue
        currentConversation?.updatedAt = .now
        messages.append(userMessage)

        guard saveContext(reportingUserError: "Failed to save your message.", logContext: "sendMessage.userMessage") else {
            return false
        }

        selectedImageData = nil
        pendingAttachments = []
        errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = currentConversation
        currentConversation?.messages.append(draft)
        saveContextIfPossible("sendMessage.draft")

        guard let session = makeStreamingSession(for: draft) else {
            errorMessage = "Failed to start response session."
            return false
        }

        registerSession(session, visible: true)
        session.isStreaming = true
        session.isThinking = false
        syncVisibleState(from: session)

        HapticService.shared.impact(.light)

        if !attachmentsToSend.isEmpty {
            Task { @MainActor in
                let uploadedAttachments = await uploadAttachments(attachmentsToSend)
                userMessage.fileAttachmentsData = FileAttachment.encode(uploadedAttachments)
                self.saveContextIfPossible("sendMessage.uploadedAttachments")
                self.startStreamingRequest(for: session)
            }
        } else {
            startStreamingRequest(for: session)
        }

        return true
    }

    // MARK: - Core Streaming Logic

    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    func startStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        startDirectStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    func startDirectStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.requestMessages else { return }

        let requestAPIKey = apiKey
        let streamID = UUID()
        session.activeStreamID = streamID
        session.isStreaming = true
        setRecoveryPhase(.idle, for: session)
        syncVisibleState(from: session)

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
                guard self.isSessionActive(session), session.activeStreamID == streamID else { break }

                switch self.applyStreamEvent(event, to: session, animated: self.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    self.finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    self.saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                    } else if !session.currentText.isEmpty {
                        self.finalizeSessionAsPartial(session)
                    } else if let message = self.findMessage(byId: session.messageID) {
                        self.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    self.saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    self.saveSessionNow(session)

                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !session.currentText.isEmpty {
                        self.finalizeSessionAsPartial(session)
                        if self.visibleSessionMessageID == session.messageID {
                            self.errorMessage = error.localizedDescription
                            HapticService.shared.notify(.error)
                        }
                    } else if let message = self.findMessage(byId: session.messageID) {
                        self.removeEmptyMessage(message, for: session)
                        if self.visibleSessionMessageID == session.messageID {
                            self.errorMessage = error.localizedDescription
                            self.clearLiveGenerationState(clearDraft: true)
                            HapticService.shared.notify(.error)
                        }
                    }
                }
            }

            guard self.isSessionActive(session), session.activeStreamID == streamID else {
                self.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                self.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                session.isStreaming = false
                setRecoveryPhase(.checkingStatus, for: session)
                if self.visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    self.errorMessage = pendingRecoveryError
                }
                self.syncVisibleState(from: session)
                self.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.requestUsesBackgroundMode
                )
                self.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = session.responseId {
                    session.isStreaming = false
                    setRecoveryPhase(.checkingStatus, for: session)
                    self.syncVisibleState(from: session)
                    self.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                    self.endBackgroundTask()
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
                        self.endBackgroundTask()
                        return
                    }

                    guard self.isSessionActive(session), session.activeStreamID == streamID else {
                        self.endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    self.startDirectStreamingRequest(for: session, reconnectAttempt: nextAttempt)
                    self.endBackgroundTask()
                    return
                }

                if !session.currentText.isEmpty {
                    self.finalizeSessionAsPartial(session)
                } else if let message = self.findMessage(byId: session.messageID) {
                    self.removeEmptyMessage(message, for: session)
                    if self.visibleSessionMessageID == session.messageID {
                        self.errorMessage = "Connection lost. Please check your network and try again."
                        self.clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }

                self.endBackgroundTask()
                return
            }

            if session.isStreaming {
                if let responseId = session.responseId {
                    self.saveSessionNow(session)
                    session.isStreaming = false
                    setRecoveryPhase(.checkingStatus, for: session)
                    self.syncVisibleState(from: session)
                    self.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                } else if !session.currentText.isEmpty {
                    self.finalizeSessionAsPartial(session)
                } else if let message = self.findMessage(byId: session.messageID) {
                    self.removeEmptyMessage(message, for: session)
                    if self.visibleSessionMessageID == session.messageID {
                        self.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            self.endBackgroundTask()
        }
    }

    // MARK: - Tool Call & Citation Persistence

    func persistToolCallsAndCitations() {
        guard let session = currentVisibleSession else { return }
        saveSessionNow(session)
    }

    // MARK: - Draft Persistence

    func saveDraftIfNeeded() {
        guard let session = currentVisibleSession else { return }
        saveSessionIfNeeded(session)
    }

    func saveDraftNow() {
        guard let session = currentVisibleSession else { return }
        saveSessionNow(session)
    }

    func finalizeDraft() {
        guard let session = currentVisibleSession else {
            clearLiveGenerationState(clearDraft: true)
            setVisibleRecoveryPhase(.idle)
            return
        }

        finalizeSession(session)
    }

    func finalizeDraftAsPartial() {
        guard let session = currentVisibleSession else { return }
        finalizeSessionAsPartial(session)
    }

    func removeEmptyDraft() {
        guard
            let session = currentVisibleSession,
            let draft = draftMessage
        else {
            return
        }

        removeEmptyMessage(draft, for: session)
    }

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        guard let session = currentVisibleSession else { return }

        let pendingBackgroundCancellation = ChatSessionDecisions.pendingBackgroundCancellation(
            requestUsesBackgroundMode: session.requestUsesBackgroundMode,
            responseId: session.responseId,
            messageId: session.messageID
        )

        session.activeStreamID = UUID()
        session.service.cancelStream()
        session.task?.cancel()
        errorMessage = nil

        if savePartial && !session.currentText.isEmpty {
            persistToolCallsAndCitations()
            finalizeSession(session)
        } else if let draft = findMessage(byId: session.messageID) {
            if !session.currentText.isEmpty {
                draft.content = session.currentText
            }
            if !session.currentThinking.isEmpty {
                draft.thinking = session.currentThinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                saveContextIfPossible("stopGeneration.persistPartialDraft")
                upsertMessage(draft)
                removeSession(session)
            } else {
                removeEmptyMessage(draft, for: session)
            }
        }

        setVisibleRecoveryPhase(.idle)
        endBackgroundTask()
        HapticService.shared.impact(.medium)

        if let pendingBackgroundCancellation {
            Task { @MainActor in
                await self.cancelBackgroundResponseAndSync(
                    responseId: pendingBackgroundCancellation.responseId,
                    messageId: pendingBackgroundCancellation.messageId
                )
            }
        }
    }
}
