import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func ensureRuntimeSessionRegistered(for session: ReplySession) {
        Task { @MainActor in
            await ensureRuntimeSessionRegisteredNow(for: session)
        }
    }

    func ensureRuntimeSessionRegisteredNow(for session: ReplySession) async {
        let alreadyRegistered = await controller.runtimeRegistry.contains(session.assistantReplyID)
        if !alreadyRegistered {
            await controller.runtimeRegistry.startSession(
                replyID: session.assistantReplyID,
                messageID: session.messageID,
                conversationID: session.conversationID
            )
        }
        guard let replySession = await controller.runtimeRegistry.session(for: session.assistantReplyID) else {
            return
        }
        let state = await replySession.snapshot()
        controller.sessionRegistry.updateRuntimeState(state, for: session.messageID)
    }

    func runtimeState(for session: ReplySession) async -> ReplyRuntimeState? {
        guard let replySession = await controller.runtimeRegistry.session(for: session.assistantReplyID) else {
            return nil
        }
        let state = await replySession.snapshot()
        controller.sessionRegistry.updateRuntimeState(state, for: session.messageID)
        return state
    }

    func cachedRuntimeState(for session: ReplySession) -> ReplyRuntimeState? {
        controller.sessionRegistry.runtimeState(for: session.messageID)
    }

    func runtimeSession(for session: ReplySession) async -> ReplySessionActor? {
        await controller.runtimeRegistry.session(for: session.assistantReplyID)
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
        controller.sessionRegistry.updateRuntimeState(state, for: session.messageID)
        return state
    }

    func runtimeRoute(for session: ReplySession) -> OpenAITransportRoute {
        let usesGateway = controller.sessionRegistry.execution(for: session.messageID)?
            .service
            .configurationProvider
            .useCloudflareGateway ?? controller.configurationProvider.useCloudflareGateway
        return usesGateway ? .gateway : .direct
    }

    func removeRuntimeSession(for session: ReplySession) {
        let assistantReplyID = session.assistantReplyID
        Task {
            await controller.runtimeRegistry.remove(assistantReplyID)
        }
    }

    func suspendActiveSessionsForAppBackground() {
        let sessions = controller.sessionRegistry.allSessions
        guard !sessions.isEmpty else { return }

        Task { @MainActor in
            for session in sessions {
                saveSessionNow(session)
                _ = await applyRuntimeTransition(
                    .detachForBackground(usedBackgroundMode: session.request.usesBackgroundMode),
                    to: session
                )
                let execution = controller.sessionRegistry.execution(for: session.messageID)
                execution?.service.cancelStream()
                execution?.task?.cancel()

                guard let message = controller.conversationCoordinator.findMessage(byId: session.messageID),
                      let runtimeState = await runtimeState(for: session) else { continue }

                if runtimeState.responseID != nil {
                    message.isComplete = false
                    message.conversation?.updatedAt = .now
                    controller.conversationCoordinator.upsertMessage(message)
                } else {
                    message.content = controller.interruptedResponseFallbackText(for: message, session: session)
                    message.thinking = runtimeState.buffer.thinking.isEmpty ? nil : runtimeState.buffer.thinking
                    message.isComplete = true
                    message.lastSequenceNumber = nil
                    message.conversation?.updatedAt = .now
                    controller.conversationCoordinator.upsertMessage(message)
                }
            }

            controller.conversationCoordinator.saveContextIfPossible("suspendActiveSessionsForAppBackground")
            controller.sessionRegistry.removeAll { execution in
                execution.task?.cancel()
                execution.service.cancelStream()
            }
            detachVisibleSessionBinding()
        }
    }
}
