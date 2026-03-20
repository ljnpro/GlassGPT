import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import ChatUIComponents
import Foundation
import OpenAITransport
import os

private let streamingSignposter = OSSignposter(subsystem: "GlassGPT", category: "streaming")

@MainActor
extension ChatStreamingCoordinator {
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

            // --- Runtime-driven terminal evaluation ---
            // Composition collects facts; runtime decides what to do next.
            let runtimeState = sessions.cachedRuntimeState(for: session)
            let canRetry = await retryStreamIfPossible(
                session: session,
                streamID: streamID,
                reconnectAttempt: reconnectAttempt,
                dryRun: true
            )
            let outcome = StreamTerminalOutcome(
                didComplete: didReceiveCompletedEvent,
                connectionLost: receivedConnectionLost,
                pendingRecoveryResponseID: pendingRecoveryResponseId,
                stateResponseID: runtimeState?.responseID,
                pendingError: pendingRecoveryError,
                hasBufferContent: !(runtimeState?.buffer.text.isEmpty ?? true),
                lastSequenceNumber: runtimeState?.lastSequenceNumber,
                usesBackgroundMode: session.request.usesBackgroundMode,
                canRetryConnection: canRetry && receivedConnectionLost
            )
            let action = StreamTerminalEvaluator.evaluate(outcome)

            // --- Composition dispatches the decided action ---
            switch action {
            case .completed:
                break

            case let .recover(responseID, lastSeq, usesBackground):
                if let error = pendingRecoveryError,
                   sessions.visibleSessionMessageID == session.messageID {
                    state.errorMessage = error
                }
                _ = await sessions.applyRuntimeTransition(
                    .beginRecoveryStatus(
                        responseID: responseID,
                        lastSequenceNumber: lastSeq,
                        usedBackgroundMode: usesBackground,
                        route: sessions.runtimeRoute(for: session)
                    ),
                    to: session
                )
                sessions.syncVisibleState(from: session)
                recovery.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseID,
                    preferStreamingResume: usesBackground,
                    visible: false
                )

            case .retryConnection:
                _ = await retryStreamIfPossible(
                    session: session,
                    streamID: streamID,
                    reconnectAttempt: reconnectAttempt
                )

            case .finalizePartial:
                sessions.finalizeSessionAsPartial(session)

            case let .removeEmptyMessage(errorMessage):
                if let message = conversations.findMessage(byId: session.messageID) {
                    sessions.removeEmptyMessage(message, for: session)
                }
                if let errorMessage, sessions.visibleSessionMessageID == session.messageID {
                    state.errorMessage = errorMessage
                    sessions.clearLiveGenerationState(clearDraft: true)
                    state.hapticService.notify(.error, isEnabled: state.hapticsEnabled)
                }
            }

            services.endBackgroundTask()
        }
    }
}
