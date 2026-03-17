import Foundation

@MainActor
extension StreamingEffectHandler {
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
}
