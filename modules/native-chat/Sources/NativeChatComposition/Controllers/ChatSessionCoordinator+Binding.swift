import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func registerSession(
        _ session: ReplySession,
        execution: SessionExecutionState,
        visible: Bool
    ) {
        registerSession(
            session,
            execution: execution,
            visible: visible,
            syncIfCurrentlyVisible: true
        )
    }

    func makeRecoverySession(for message: Message) -> ReplySession? {
        guard let conversation = message.conversation else { return nil }
        return ChatRecoverySessionFactory.makeSession(
            for: message,
            conversationID: conversation.id,
            configuration: conversations.sessionRequestConfiguration(for: conversation),
            apiKey: services.apiKeyStore.loadAPIKey() ?? ""
        )
    }

    func registerSession(
        _ session: ReplySession,
        execution: SessionExecutionState,
        visible: Bool,
        syncIfCurrentlyVisible: Bool
    ) {
        services.sessionRegistry.register(session, execution: execution, visible: visible) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }
        ensureRuntimeSessionRegistered(for: session)

        if visible {
            bindVisibleSession(messageID: session.messageID)
        } else if syncIfCurrentlyVisible, visibleSessionMessageID == session.messageID {
            syncVisibleState(from: session)
        }
    }

    func isSessionActive(_ session: ReplySession) -> Bool {
        services.sessionRegistry.contains(session)
    }
}
