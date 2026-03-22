import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func ensureRuntimeSessionRegistered(for session: ReplySession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await ensureRuntimeSessionRegisteredNow(for: session)
        }
    }

    func ensureRuntimeSessionRegisteredNow(for session: ReplySession) async {
        let alreadyRegistered = await services.runtimeRegistry.contains(session.assistantReplyID)
        if !alreadyRegistered {
            await services.runtimeRegistry.startSession(initialState: initialRuntimeState(for: session))
        }
        guard let replySession = await services.runtimeRegistry.session(for: session.assistantReplyID) else {
            return
        }
        let state = await replySession.snapshot()
        services.sessionRegistry.updateRuntimeState(state, for: session.messageID)
    }

    func runtimeState(for session: ReplySession) async -> ReplyRuntimeState? {
        guard let replySession = await services.runtimeRegistry.session(for: session.assistantReplyID) else {
            return nil
        }
        let state = await replySession.snapshot()
        services.sessionRegistry.updateRuntimeState(state, for: session.messageID)
        return state
    }

    func cachedRuntimeState(for session: ReplySession) -> ReplyRuntimeState? {
        services.sessionRegistry.runtimeState(for: session.messageID)
    }

    func runtimeSession(for session: ReplySession) async -> ReplySessionActor? {
        await services.runtimeRegistry.session(for: session.assistantReplyID)
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
        services.sessionRegistry.updateRuntimeState(state, for: session.messageID)
        return state
    }

    func runtimeRoute(for session: ReplySession) -> OpenAITransportRoute {
        let usesGateway = services.sessionRegistry.execution(for: session.messageID)?
            .service
            .configurationProvider
            .useCloudflareGateway ?? services.configurationProvider.useCloudflareGateway
        return usesGateway ? .gateway : .direct
    }

    func removeRuntimeSession(for session: ReplySession) {
        let assistantReplyID = session.assistantReplyID
        let runtimeRegistry = services.runtimeRegistry
        Task {
            await runtimeRegistry.remove(assistantReplyID)
        }
    }

    private func initialRuntimeState(for session: ReplySession) -> ReplyRuntimeState {
        guard let message = conversations.findMessage(byId: session.messageID) else {
            return ReplyRuntimeState(
                assistantReplyID: session.assistantReplyID,
                messageID: session.messageID,
                conversationID: session.conversationID,
                lifecycle: .preparingInput
            )
        }

        return ReplyRuntimeState(
            assistantReplyID: session.assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: .preparingInput,
            buffer: ReplyBuffer(
                text: message.content,
                thinking: message.thinking ?? "",
                toolCalls: message.toolCalls,
                citations: message.annotations,
                filePathAnnotations: message.filePathAnnotations,
                attachments: message.fileAttachments
            ),
            isThinking: inferredRecoveryThinkingState(from: message)
        )
    }

    private func inferredRecoveryThinkingState(from message: Message) -> Bool {
        guard !message.isComplete, message.responseId != nil else {
            return false
        }

        if let thinking = message.thinking, !thinking.isEmpty {
            return true
        }

        return message.toolCalls.contains { $0.status != .completed }
    }

    func suspendActiveSessionsForAppBackground() {
        let sessions = services.sessionRegistry.allSessions
        services.cancelGeneratedFilePrefetches(services.generatedFilePrefetchRegistry.cancelAll())
        guard !sessions.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for session in sessions {
                let assistantReplyID = session.assistantReplyID
                saveSessionNow(session)
                _ = await applyRuntimeTransition(
                    .detachForBackground(usedBackgroundMode: session.request.usesBackgroundMode),
                    to: session
                )
                let execution = services.sessionRegistry.execution(for: session.messageID)
                execution?.service.cancelStream()
                execution?.task?.cancel()

                guard let message = conversations.findMessage(byId: session.messageID),
                      let runtimeState = await runtimeState(for: session) else {
                    await services.runtimeRegistry.remove(assistantReplyID)
                    continue
                }

                if runtimeState.responseID != nil {
                    message.isComplete = false
                    message.conversation?.updatedAt = .now
                    conversations.upsertMessage(message)
                } else {
                    message.content = interruptedResponseFallbackText(
                        recoveryFallbackText(
                            for: message,
                            session: session,
                            runtimeState: cachedRuntimeState(for: session),
                            visibleSessionMessageID: visibleSessionMessageID,
                            currentStreamingText: state.currentStreamingText
                        )
                    )
                    message.thinking = runtimeState.buffer.thinking.isEmpty ? nil : runtimeState.buffer.thinking
                    message.isComplete = true
                    message.lastSequenceNumber = nil
                    message.conversation?.updatedAt = .now
                    conversations.upsertMessage(message)
                }

                await services.runtimeRegistry.remove(assistantReplyID)
            }

            conversations.saveContextIfPossible("suspendActiveSessionsForAppBackground")
            services.sessionRegistry.removeAll { execution in
                execution.task?.cancel()
                execution.service.cancelStream()
            }
            detachVisibleSessionBinding()
        }
    }
}
