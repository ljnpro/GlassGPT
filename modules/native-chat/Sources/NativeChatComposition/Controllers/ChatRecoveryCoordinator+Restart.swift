import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    @discardableResult
    func restartMessageAfterRecoveryExhausted(
        _ message: Message,
        session: ReplySession,
        visible: Bool,
        errorMessage: String?
    ) async -> Bool {
        if visible, let errorMessage {
            state.errorMessage = errorMessage
        }

        guard message.role == .assistant, !message.isComplete else {
            resultApplier.finishRecovery(
                for: message,
                session: session,
                result: nil,
                fallbackText: resultApplier.recoveryFallbackText(for: message, session: session),
                fallbackThinking: resultApplier.recoveryFallbackThinking(for: message, session: session)
            )
            return false
        }

        guard let preparedReply = prepareRestartedRecoveryReply(for: message, visible: visible) else {
            resultApplier.finishRecovery(
                for: message,
                session: session,
                result: nil,
                fallbackText: resultApplier.recoveryFallbackText(for: message, session: session),
                fallbackThinking: resultApplier.recoveryFallbackThinking(for: message, session: session)
            )
            return false
        }

        await services.runtimeRegistry.remove(session.assistantReplyID)
        sessions.removeSessionWithoutRefreshingVisibleBinding(
            session,
            cancelExecutionTask: false,
            cancelStream: false
        )

        resetDraftForRestart(message, preparedReply: preparedReply)
        conversations.upsertMessage(message)
        conversations.saveContextIfPossible("restartRecoveredDraftIfPossible.resetDraft")

        let restartedSession = ReplySession(preparedReply: preparedReply)
        sessions.registerSession(
            restartedSession,
            execution: SessionExecutionState(service: services.serviceFactory()),
            visible: visible,
            syncIfCurrentlyVisible: true
        )
        _ = await sessions.applyRuntimeTransition(.beginSubmitting, to: restartedSession)
        _ = await sessions.applyRuntimeTransition(.setThinking(true), to: restartedSession)
        _ = await sessions.applyRuntimeTransition(.setRecoveryRestartPending(true), to: restartedSession)
        if visible {
            sessions.syncVisibleState(from: restartedSession)
        }

        state.errorMessage = nil
        streaming.startStreamingRequest(for: restartedSession, reconnectAttempt: 0)
        Loggers.recovery.debug("[Recovery] Restarted draft request for message \(message.id.uuidString)")
        return true
    }
}
