import Foundation
import ChatApplication
import ChatDomain
import ChatRuntimeModel
import ChatRuntimePorts
import ChatRuntimeWorkflows

@MainActor
final class ChatRuntimeEngine {
    unowned let viewModel: any ChatRuntimeScreenStore
    let runtimeRegistry: RuntimeRegistryActor
    let chatSceneController: ChatSceneController
    let storeActor = NativeChatStoreActor()
    let sessionStateStore: SessionProjectionStore
    let streamEventCoordinator: StreamEventCoordinator
    let recoveryCoordinator: RecoveryEffectHandler
    let streamingCoordinator: StreamingEffectHandler

    init(
        viewModel: any ChatRuntimeScreenStore,
        runtimeRegistry: RuntimeRegistryActor,
        chatSceneController: ChatSceneController,
        sendPreparationPort: any SendMessagePreparationPort
    ) {
        self.viewModel = viewModel
        self.runtimeRegistry = runtimeRegistry
        self.chatSceneController = chatSceneController
        let sessionStateStore = SessionProjectionStore(viewModel: viewModel)
        let streamEventCoordinator = StreamEventCoordinator(viewModel: viewModel)
        let recoveryCoordinator = RecoveryEffectHandler(viewModel: viewModel)
        let streamingCoordinator = StreamingEffectHandler(
            viewModel: viewModel,
            recoveryCoordinator: recoveryCoordinator,
            chatSceneController: chatSceneController,
            sendPreparationPort: sendPreparationPort
        )
        self.sessionStateStore = sessionStateStore
        self.streamEventCoordinator = streamEventCoordinator
        self.recoveryCoordinator = recoveryCoordinator
        self.streamingCoordinator = streamingCoordinator
    }

    func applyVisibleProjection(
        _ projection: ChatVisibleProjection,
        visibleMessageID: UUID?
    ) {
        Task {
            _ = await storeActor.send(
                .applyVisibleProjection(
                    visibleMessageID: visibleMessageID,
                    projection: projection
                )
            )
        }
    }

    func setConversationProjection(_ conversationID: UUID?) {
        Task {
            _ = await storeActor.send(.setConversation(conversationID))
        }
    }

    func ensureRuntimeSessionRegistered(for session: ResponseSession) {
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

    func syncRuntimeSession(from session: ResponseSession, attachments: [FileAttachment]) {
        let assistantReplyID = session.assistantReplyID
        let route: OpenAITransportRoute = session.service.configurationProvider.useCloudflareGateway ? .gateway : .direct
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
                    usedBackgroundMode: session.requestUsesBackgroundMode,
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
                    usedBackgroundMode: session.requestUsesBackgroundMode,
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

    func removeRuntimeSession(for session: ResponseSession) {
        let assistantReplyID = session.assistantReplyID
        Task {
            await runtimeRegistry.remove(assistantReplyID)
        }
    }
}
