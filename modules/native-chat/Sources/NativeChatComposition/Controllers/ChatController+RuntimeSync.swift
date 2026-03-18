import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation

@MainActor
extension ChatController {
    func ensureRuntimeSessionRegistered(for session: ReplySession) {
        Task { @MainActor in
            await ensureRuntimeSessionRegisteredNow(for: session)
        }
    }

    func ensureRuntimeSessionRegisteredNow(for session: ReplySession) async {
        let alreadyRegistered = await runtimeRegistry.contains(session.assistantReplyID)
        if !alreadyRegistered {
            await runtimeRegistry.startSession(
                replyID: session.assistantReplyID,
                messageID: session.messageID,
                conversationID: session.conversationID
            )
        }
        guard let replySession = await runtimeRegistry.session(for: session.assistantReplyID) else {
            return
        }
        let state = await replySession.snapshot()
        sessionRegistry.updateRuntimeState(state, for: session.messageID)
    }

    func runtimeState(for session: ReplySession) async -> ReplyRuntimeState? {
        guard let replySession = await runtimeRegistry.session(for: session.assistantReplyID) else {
            return nil
        }
        let state = await replySession.snapshot()
        sessionRegistry.updateRuntimeState(state, for: session.messageID)
        return state
    }

    func cachedRuntimeState(for session: ReplySession) -> ReplyRuntimeState? {
        sessionRegistry.runtimeState(for: session.messageID)
    }

    func runtimeSession(for session: ReplySession) async -> ReplySessionActor? {
        await runtimeRegistry.session(for: session.assistantReplyID)
    }

    func applyRuntimeTransition(
        _ transition: ReplyRuntimeTransition,
        to session: ReplySession
    ) async -> ReplyRuntimeState? {
        await ensureRuntimeSessionRegisteredNow(for: session)
        guard let runtimeActor = await runtimeSession(for: session) else {
            return nil
        }
        let state = await runtimeActor.apply(transition)
        sessionRegistry.updateRuntimeState(state, for: session.messageID)
        return state
    }

    func runtimeRoute(for session: ReplySession) -> OpenAITransportRoute {
        let usesGateway = sessionRegistry.execution(for: session.messageID)?
            .service
            .configurationProvider
            .useCloudflareGateway ?? configurationProvider.useCloudflareGateway
        return usesGateway ? .gateway : .direct
    }

    func removeRuntimeSession(for session: ReplySession) {
        let assistantReplyID = session.assistantReplyID
        Task {
            await runtimeRegistry.remove(assistantReplyID)
        }
    }

    func suspendActiveSessionsForAppBackground() {
        let sessions = sessionRegistry.allSessions
        guard !sessions.isEmpty else { return }

        Task { @MainActor in
            for session in sessions {
                saveSessionNow(session)
                _ = await applyRuntimeTransition(
                    .detachForBackground(usedBackgroundMode: session.request.usesBackgroundMode),
                    to: session
                )
                let execution = sessionRegistry.execution(for: session.messageID)
                execution?.service.cancelStream()
                execution?.task?.cancel()

                guard let message = findMessage(byId: session.messageID),
                      let runtimeState = await runtimeState(for: session) else { continue }

                if runtimeState.responseID != nil {
                    message.isComplete = false
                    message.conversation?.updatedAt = .now
                    upsertMessage(message)
                } else {
                    message.content = interruptedResponseFallbackText(for: message, session: session)
                    message.thinking = runtimeState.buffer.thinking.isEmpty ? nil : runtimeState.buffer.thinking
                    message.isComplete = true
                    message.lastSequenceNumber = nil
                    message.conversation?.updatedAt = .now
                    upsertMessage(message)
                }
            }

            saveContextIfPossible("suspendActiveSessionsForAppBackground")
            sessionRegistry.removeAll { execution in
                execution.task?.cancel()
                execution.service.cancelStream()
            }
            detachVisibleSessionBinding()
        }
    }
}
