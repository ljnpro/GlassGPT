import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func bindVisibleSession(messageID: UUID?) {
        services.sessionRegistry.bindVisibleSession(messageID: messageID)

        guard
            let messageID,
            let session = services.sessionRegistry.session(for: messageID),
            let message = conversations.findMessage(byId: messageID),
            state.currentConversation?.id == session.conversationID
        else {
            state.draftMessage = nil
            SessionVisibilityCoordinator.apply(
                SessionVisibilityCoordinator.clearedState(
                    retaining: state.draftMessage,
                    clearDraft: false
                ),
                to: state
            )
            return
        }

        state.draftMessage = message
        syncVisibleState(from: session)
        conversations.upsertMessage(message)
    }

    func detachVisibleSessionBinding() {
        services.sessionRegistry.bindVisibleSession(messageID: nil)
        state.draftMessage = nil
        SessionVisibilityCoordinator.apply(
            SessionVisibilityCoordinator.clearedState(
                retaining: state.draftMessage,
                clearDraft: false
            ),
            to: state
        )
        state.errorMessage = nil
    }

    func syncVisibleState(from session: ReplySession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard SessionVisibilityCoordinator.canApplyVisibleState(
                targetSession: session,
                visibleMessageID: visibleSessionMessageID,
                currentConversationID: state.currentConversation?.id,
                registeredSession: services.sessionRegistry.session(for: session.messageID)
            ) else {
                return
            }
            guard let runtimeState = await runtimeState(for: session) else { return }
            guard SessionVisibilityCoordinator.canApplyVisibleState(
                targetSession: session,
                visibleMessageID: visibleSessionMessageID,
                currentConversationID: state.currentConversation?.id,
                registeredSession: services.sessionRegistry.session(for: session.messageID)
            ) else {
                return
            }

            let state = SessionVisibilityCoordinator.visibleState(
                from: session,
                runtimeState: runtimeState,
                draftMessage: conversations.findMessage(byId: session.messageID)
            )
            SessionVisibilityCoordinator.apply(state, to: self.state)
        }
    }

    func refreshVisibleBindingForCurrentConversation() {
        guard let conversation = state.currentConversation else {
            detachVisibleSessionBinding()
            return
        }

        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { services.sessionRegistry.session(for: $0.id) != nil }) {
            bindVisibleSession(messageID: message.id)
            return
        }

        if let message = activeMessages.last {
            services.sessionRegistry.bindVisibleSession(messageID: message.id)
            if message.responseId != nil {
                SessionVisibilityCoordinator.apply(
                    SessionVisibilityCoordinator.recoverableDraftPlaceholderState(
                        for: message,
                        requestConfiguration: message.conversation.map {
                            conversations.sessionRequestConfiguration(for: $0)
                        }
                    ),
                    to: state
                )
            } else {
                SessionVisibilityCoordinator.apply(
                    SessionVisibilityCoordinator.clearedState(
                        retaining: state.draftMessage,
                        clearDraft: false
                    ),
                    to: state
                )
                state.draftMessage = message
            }
        } else {
            detachVisibleSessionBinding()
        }
    }

    func clearLiveGenerationState(clearDraft: Bool) {
        SessionVisibilityCoordinator.apply(
            SessionVisibilityCoordinator.clearedState(
                retaining: state.draftMessage,
                clearDraft: clearDraft
            ),
            to: state
        )
    }
}
