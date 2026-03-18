import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatController {
    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.request.messages else { return }
        guard let execution = sessionRegistry.execution(for: session.messageID) else { return }

        let streamID = UUID()
        session.beginStreaming(streamID: streamID)
        setRecoveryPhase(.idle, for: session)
        syncVisibleState(from: session)

        execution.task?.cancel()
        execution.task = Task { @MainActor in
            let stream = execution.service.streamChat(
                apiKey: session.request.apiKey,
                messages: requestMessages,
                model: session.request.model,
                reasoningEffort: session.request.effort,
                backgroundModeEnabled: session.request.usesBackgroundMode,
                serviceTier: session.request.serviceTier
            )

            var receivedConnectionLost = false
            var didReceiveCompletedEvent = false
            var pendingRecoveryResponseId: String?
            var pendingRecoveryError: String?

            for await event in stream {
                guard isSessionActive(session), session.activeStreamID == streamID else { break }

                switch applyStreamEvent(event, to: session, animated: visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                    } else if !session.currentText.isEmpty {
                        finalizeSessionAsPartial(session)
                    } else if let message = findMessage(byId: session.messageID) {
                        removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !session.currentText.isEmpty {
                        finalizeSessionAsPartial(session)
                        if visibleSessionMessageID == session.messageID {
                            errorMessage = error.localizedDescription
                            HapticService.shared.notify(.error)
                        }
                    } else if let message = findMessage(byId: session.messageID) {
                        removeEmptyMessage(message, for: session)
                        if visibleSessionMessageID == session.messageID {
                            errorMessage = error.localizedDescription
                            clearLiveGenerationState(clearDraft: true)
                            HapticService.shared.notify(.error)
                        }
                    }
                }
            }

            guard isSessionActive(session), session.activeStreamID == streamID else {
                endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                session.setRecoveryPhase(.checkingStatus)
                setRecoveryPhase(.checkingStatus, for: session)
                if visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    errorMessage = pendingRecoveryError
                }
                syncVisibleState(from: session)
                recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.request.usesBackgroundMode
                )
                endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = session.responseId {
                    session.setRecoveryPhase(.checkingStatus)
                    setRecoveryPhase(.checkingStatus, for: session)
                    syncVisibleState(from: session)
                    recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode
                    )
                    endBackgroundTask()
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
                        endBackgroundTask()
                        return
                    }

                    guard isSessionActive(session), session.activeStreamID == streamID else {
                        endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    startStreamingRequest(for: session, reconnectAttempt: nextAttempt)
                    endBackgroundTask()
                    return
                }

                if !session.currentText.isEmpty {
                    finalizeSessionAsPartial(session)
                } else if let message = findMessage(byId: session.messageID) {
                    removeEmptyMessage(message, for: session)
                    if visibleSessionMessageID == session.messageID {
                        errorMessage = "Connection lost. Please check your network and try again."
                        clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }

                endBackgroundTask()
                return
            }

            if session.isStreaming {
                if let responseId = session.responseId {
                    saveSessionNow(session)
                    session.setRecoveryPhase(.checkingStatus)
                    setRecoveryPhase(.checkingStatus, for: session)
                    syncVisibleState(from: session)
                    recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode
                    )
                } else if !session.currentText.isEmpty {
                    finalizeSessionAsPartial(session)
                } else if let message = findMessage(byId: session.messageID) {
                    removeEmptyMessage(message, for: session)
                    if visibleSessionMessageID == session.messageID {
                        clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            endBackgroundTask()
        }
    }
}
