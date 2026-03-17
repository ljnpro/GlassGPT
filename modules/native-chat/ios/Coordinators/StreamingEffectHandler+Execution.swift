import Foundation

@MainActor
extension StreamingEffectHandler {
    func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = viewModel.currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    func startStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.requestMessages else { return }

        let viewModel = self.viewModel
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
                guard viewModel.isSessionActive(session), session.activeStreamID == streamID else { break }

                switch viewModel.applyStreamEvent(event, to: session, animated: viewModel.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    viewModel.finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    viewModel.saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                    } else if !session.currentText.isEmpty {
                        viewModel.finalizeSessionAsPartial(session)
                    } else if let message = viewModel.findMessage(byId: session.messageID) {
                        viewModel.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    viewModel.saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    viewModel.saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !session.currentText.isEmpty {
                        viewModel.finalizeSessionAsPartial(session)
                        if viewModel.visibleSessionMessageID == session.messageID {
                            viewModel.errorMessage = error.localizedDescription
                            HapticService.shared.notify(.error)
                        }
                    } else if let message = viewModel.findMessage(byId: session.messageID) {
                        viewModel.removeEmptyMessage(message, for: session)
                        if viewModel.visibleSessionMessageID == session.messageID {
                            viewModel.errorMessage = error.localizedDescription
                            viewModel.clearLiveGenerationState(clearDraft: true)
                            HapticService.shared.notify(.error)
                        }
                    }
                }
            }

            guard viewModel.isSessionActive(session), session.activeStreamID == streamID else {
                viewModel.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                viewModel.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                session.setRecoveryPhase(.checkingStatus)
                viewModel.setRecoveryPhase(.checkingStatus, for: session)
                if viewModel.visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    viewModel.errorMessage = pendingRecoveryError
                }
                viewModel.syncVisibleState(from: session)
                self.recoveryCoordinator.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.requestUsesBackgroundMode
                )
                viewModel.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = session.responseId {
                    session.setRecoveryPhase(.checkingStatus)
                    viewModel.setRecoveryPhase(.checkingStatus, for: session)
                    viewModel.syncVisibleState(from: session)
                    self.recoveryCoordinator.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                    viewModel.endBackgroundTask()
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
                        viewModel.endBackgroundTask()
                        return
                    }

                    guard viewModel.isSessionActive(session), session.activeStreamID == streamID else {
                        viewModel.endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    self.startStreamingRequest(for: session, reconnectAttempt: nextAttempt)
                    viewModel.endBackgroundTask()
                    return
                }

                if !session.currentText.isEmpty {
                    viewModel.finalizeSessionAsPartial(session)
                } else if let message = viewModel.findMessage(byId: session.messageID) {
                    viewModel.removeEmptyMessage(message, for: session)
                    if viewModel.visibleSessionMessageID == session.messageID {
                        viewModel.errorMessage = "Connection lost. Please check your network and try again."
                        viewModel.clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }

                viewModel.endBackgroundTask()
                return
            }

            if session.isStreaming {
                if let responseId = session.responseId {
                    viewModel.saveSessionNow(session)
                    session.setRecoveryPhase(.checkingStatus)
                    viewModel.setRecoveryPhase(.checkingStatus, for: session)
                    viewModel.syncVisibleState(from: session)
                    self.recoveryCoordinator.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                } else if !session.currentText.isEmpty {
                    viewModel.finalizeSessionAsPartial(session)
                } else if let message = viewModel.findMessage(byId: session.messageID) {
                    viewModel.removeEmptyMessage(message, for: session)
                    if viewModel.visibleSessionMessageID == session.messageID {
                        viewModel.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            viewModel.endBackgroundTask()
        }
    }
}
