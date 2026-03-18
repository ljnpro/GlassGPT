import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatController {
    func ensureRuntimeSessionRegistered(for session: ReplySession) {
        let replyID = session.assistantReplyID
        Task {
            let alreadyRegistered = await runtimeRegistry.contains(replyID)
            guard !alreadyRegistered else { return }
            await runtimeRegistry.startSession(
                replyID: replyID,
                messageID: session.messageID,
                conversationID: session.conversationID
            )
        }
    }

    func syncRuntimeSession(from session: ReplySession) {
        let attachments = findMessage(byId: session.messageID)?.fileAttachments ?? []
        let assistantReplyID = session.assistantReplyID
        let usesGateway = sessionRegistry.execution(for: session.messageID)?
            .service
            .configurationProvider
            .useCloudflareGateway ?? configurationProvider.useCloudflareGateway
        let route: OpenAITransportRoute = usesGateway ? .gateway : .direct
        let cursor = session.responseId.map {
            StreamCursor(
                responseID: $0,
                lastSequenceNumber: session.lastSequenceNumber,
                route: route
            )
        }

        let lifecycle: ReplyLifecycle
        switch session.phase {
        case .idle:
            lifecycle = .idle
        case .submitting:
            lifecycle = .preparingInput
        case .streaming:
            lifecycle = cursor.map(ReplyLifecycle.streaming) ?? .preparingInput
        case .recoveringStatus:
            if let cursor {
                let ticket = DetachedRecoveryTicket(
                    assistantReplyID: assistantReplyID,
                    messageID: session.messageID,
                    conversationID: session.conversationID,
                    responseID: cursor.responseID,
                    lastSequenceNumber: cursor.lastSequenceNumber,
                    usedBackgroundMode: session.request.usesBackgroundMode,
                    route: cursor.route
                )
                lifecycle = .recoveringStatus(ticket)
            } else {
                lifecycle = .preparingInput
            }
        case .recoveringStream:
            lifecycle = cursor.map(ReplyLifecycle.recoveringStream) ?? .preparingInput
        case .recoveringPoll:
            if let cursor {
                let ticket = DetachedRecoveryTicket(
                    assistantReplyID: assistantReplyID,
                    messageID: session.messageID,
                    conversationID: session.conversationID,
                    responseID: cursor.responseID,
                    lastSequenceNumber: cursor.lastSequenceNumber,
                    usedBackgroundMode: session.request.usesBackgroundMode,
                    route: cursor.route
                )
                lifecycle = .recoveringPoll(ticket)
            } else {
                lifecycle = .preparingInput
            }
        case .finalizing:
            lifecycle = .finalizing
        case .completed:
            lifecycle = .completed
        case .failed:
            lifecycle = .failed(nil)
        }

        let state = ReplyRuntimeState(
            assistantReplyID: assistantReplyID,
            messageID: session.messageID,
            conversationID: session.conversationID,
            lifecycle: lifecycle,
            buffer: ReplyBuffer(
                text: session.currentText,
                thinking: session.currentThinking,
                toolCalls: session.toolCalls,
                citations: session.citations,
                filePathAnnotations: session.filePathAnnotations,
                attachments: attachments
            ),
            cursor: cursor
        )

        Task {
            guard let replySession = await runtimeRegistry.session(for: assistantReplyID) else { return }
            await replySession.replaceState(with: state)
        }
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

        for session in sessions {
            saveSessionNow(session)
            session.cancelStreaming()
            let execution = sessionRegistry.execution(for: session.messageID)
            execution?.service.cancelStream()
            execution?.task?.cancel()

            guard let message = findMessage(byId: session.messageID) else { continue }

            if session.responseId != nil {
                message.isComplete = false
                message.conversation?.updatedAt = .now
                upsertMessage(message)
            } else {
                message.content = interruptedResponseFallbackText(for: message, session: session)
                message.thinking = session.currentThinking.isEmpty ? nil : session.currentThinking
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
