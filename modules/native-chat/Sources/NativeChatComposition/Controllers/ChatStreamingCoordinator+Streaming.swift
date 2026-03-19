import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import OpenAITransport
import os

private let streamingSignposter = OSSignposter(subsystem: "GlassGPT", category: "streaming")

@MainActor
extension ChatStreamingCoordinator {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int = 0) {
        let signpostID = streamingSignposter.makeSignpostID()
        let signpostState = streamingSignposter.beginInterval("StreamingRequest", id: signpostID)
        defer { streamingSignposter.endInterval("StreamingRequest", signpostState) }

        guard let requestMessages = session.request.messages else { return }
        guard let execution = services.sessionRegistry.execution(for: session.messageID) else { return }

        execution.task?.cancel()
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            let streamID = UUID()
            _ = await sessions.applyRuntimeTransition(
                .beginStreaming(
                    streamID: streamID,
                    route: sessions.runtimeRoute(for: session)
                ),
                to: session
            )
            sessions.syncVisibleState(from: session)

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
                guard sessions.isSessionActive(session),
                      let runtimeActor = await sessions.runtimeSession(for: session),
                      await runtimeActor.isActiveStream(streamID)
                else {
                    break
                }

                switch await applyStreamEvent(event, to: session, animated: sessions.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    sessions.finalizeSession(session)

                case let .terminalIncomplete(message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    sessions.saveSessionNow(session)
                    if let responseId = sessions.cachedRuntimeState(for: session)?.responseID {
                        pendingRecoveryResponseId = responseId
                    } else if !(sessions.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                        sessions.finalizeSessionAsPartial(session)
                    } else if let message = conversations.findMessage(byId: session.messageID) {
                        sessions.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    sessions.saveSessionNow(session)
                    #if DEBUG
                    Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case let .terminalFailure(message):
                    sessions.saveSessionNow(session)
                    if let responseId = sessions.cachedRuntimeState(for: session)?.responseID {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = message
                        #if DEBUG
                        Loggers.chat.debug("[VM] Stream error, attempting recovery: \(message)")
                        #endif
                    } else if !(sessions.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                        sessions.finalizeSessionAsPartial(session)
                        if sessions.visibleSessionMessageID == session.messageID {
                            state.errorMessage = message
                            state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
                        }
                    } else if let draftMessage = conversations.findMessage(byId: session.messageID) {
                        sessions.removeEmptyMessage(draftMessage, for: session)
                        if sessions.visibleSessionMessageID == session.messageID {
                            state.errorMessage = message
                            sessions.clearLiveGenerationState(clearDraft: true)
                            state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
                        }
                    }
                }
            }

            guard sessions.isSessionActive(session),
                  let runtimeActor = await sessions.runtimeSession(for: session),
                  await runtimeActor.isActiveStream(streamID)
            else {
                services.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                services.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                let shouldSurfacePendingRecoveryError =
                    sessions.visibleSessionMessageID == session.messageID &&
                    (pendingRecoveryError?.isEmpty == false)
                _ = await sessions.applyRuntimeTransition(
                    .beginRecoveryStatus(
                        responseID: responseId,
                        lastSequenceNumber: sessions.cachedRuntimeState(for: session)?.lastSequenceNumber,
                        usedBackgroundMode: session.request.usesBackgroundMode,
                        route: sessions.runtimeRoute(for: session)
                    ),
                    to: session
                )
                if shouldSurfacePendingRecoveryError, let pendingRecoveryError {
                    state.errorMessage = pendingRecoveryError
                }
                sessions.syncVisibleState(from: session)
                recovery.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.request.usesBackgroundMode,
                    visible: false
                )
                services.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = sessions.cachedRuntimeState(for: session)?.responseID {
                    _ = await sessions.applyRuntimeTransition(
                        .beginRecoveryStatus(
                            responseID: responseId,
                            lastSequenceNumber: sessions.cachedRuntimeState(for: session)?.lastSequenceNumber,
                            usedBackgroundMode: session.request.usesBackgroundMode,
                            route: sessions.runtimeRoute(for: session)
                        ),
                        to: session
                    )
                    sessions.syncVisibleState(from: session)
                    recovery.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode,
                        visible: false
                    )
                    services.endBackgroundTask()
                    return
                }

                if await retryStreamIfPossible(
                    session: session,
                    streamID: streamID,
                    reconnectAttempt: reconnectAttempt
                ) {
                    services.endBackgroundTask()
                    return
                }

                if !(sessions.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                    sessions.finalizeSessionAsPartial(session)
                } else if let message = conversations.findMessage(byId: session.messageID) {
                    sessions.removeEmptyMessage(message, for: session)
                    if sessions.visibleSessionMessageID == session.messageID {
                        state.errorMessage = "Connection lost. Please check your network and try again."
                        sessions.clearLiveGenerationState(clearDraft: true)
                        state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
                    }
                }

                services.endBackgroundTask()
                return
            }

            if sessions.cachedRuntimeState(for: session)?.isStreaming == true {
                if let responseId = sessions.cachedRuntimeState(for: session)?.responseID {
                    sessions.saveSessionNow(session)
                    _ = await sessions.applyRuntimeTransition(
                        .beginRecoveryStatus(
                            responseID: responseId,
                            lastSequenceNumber: sessions.cachedRuntimeState(for: session)?.lastSequenceNumber,
                            usedBackgroundMode: session.request.usesBackgroundMode,
                            route: sessions.runtimeRoute(for: session)
                        ),
                        to: session
                    )
                    sessions.syncVisibleState(from: session)
                    recovery.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.request.usesBackgroundMode,
                        visible: false
                    )
                } else if !(sessions.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                    sessions.finalizeSessionAsPartial(session)
                } else if let message = conversations.findMessage(byId: session.messageID) {
                    sessions.removeEmptyMessage(message, for: session)
                    if sessions.visibleSessionMessageID == session.messageID {
                        sessions.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            services.endBackgroundTask()
        }
    }
}
