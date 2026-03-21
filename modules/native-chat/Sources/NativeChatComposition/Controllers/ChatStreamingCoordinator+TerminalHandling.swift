import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatStreamingCoordinator {
    func handleStreamingEvent(
        _ event: StreamEvent,
        session: ReplySession,
        streamID: UUID,
        progress: StreamingProgress
    ) async -> Bool {
        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID)
        else {
            return false
        }

        switch await applyStreamEvent(event, to: session, animated: sessions.visibleSessionMessageID == session.messageID) {
        case .continued:
            break

        case .terminalCompleted:
            progress.didReceiveCompletedEvent = true
            sessions.finalizeSession(session)

        case let .terminalIncomplete(message):
            progress.pendingRecoveryError = message ?? "Response was incomplete."
            sessions.saveSessionNow(session)
            if let responseId = sessions.cachedRuntimeState(for: session)?.responseID {
                progress.pendingRecoveryResponseId = responseId
            } else if !(sessions.cachedRuntimeState(for: session)?.buffer.text.isEmpty ?? true) {
                sessions.finalizeSessionAsPartial(session)
            } else if let message = conversations.findMessage(byId: session.messageID) {
                sessions.removeEmptyMessage(message, for: session)
            }

        case .connectionLost:
            progress.receivedConnectionLost = true
            sessions.saveSessionNow(session)
            #if DEBUG
            Loggers.chat.debug("[VM] Connection lost for session \(session.messageID)")
            #endif

        case let .terminalFailure(message):
            sessions.saveSessionNow(session)
            if let responseId = sessions.cachedRuntimeState(for: session)?.responseID {
                progress.pendingRecoveryResponseId = responseId
                progress.pendingRecoveryError = message
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

        return true
    }

    func finishStreamingRequest(
        session: ReplySession,
        streamID: UUID,
        reconnectAttempt: Int,
        progress: StreamingProgress
    ) async {
        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID)
        else {
            return
        }

        let runtimeState = sessions.cachedRuntimeState(for: session)
        let canRetry = await retryStreamIfPossible(
            session: session,
            streamID: streamID,
            reconnectAttempt: reconnectAttempt,
            dryRun: true
        )
        let outcome = StreamTerminalOutcome(
            didComplete: progress.didReceiveCompletedEvent,
            connectionLost: progress.receivedConnectionLost,
            pendingRecoveryResponseID: progress.pendingRecoveryResponseId,
            stateResponseID: runtimeState?.responseID,
            pendingError: progress.pendingRecoveryError,
            hasBufferContent: !(runtimeState?.buffer.text.isEmpty ?? true),
            lastSequenceNumber: runtimeState?.lastSequenceNumber,
            usesBackgroundMode: session.request.usesBackgroundMode,
            canRetryConnection: canRetry && progress.receivedConnectionLost
        )
        let action = StreamTerminalEvaluator.evaluate(outcome)

        switch action {
        case .completed:
            break

        case let .recover(responseID, lastSeq, usesBackground):
            if let error = progress.pendingRecoveryError,
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
    }
}
