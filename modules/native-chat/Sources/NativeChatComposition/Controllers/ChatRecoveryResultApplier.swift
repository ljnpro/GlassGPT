import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
final class ChatRecoveryResultApplier {
    unowned let state: any (
        ChatConversationSelectionAccess &
            ChatStreamingProjectionAccess &
            ChatReplyFeedbackAccess
    )
    unowned let services: any (
        ChatPersistenceAccess &
            ChatTransportServiceAccess &
            ChatGeneratedFileServiceAccess &
            ChatRuntimeRegistryAccess
    )
    unowned var conversations: (any ChatConversationManaging)!
    unowned var sessions: (any ChatSessionManaging)!
    unowned var files: (any ChatFileInteractionManaging)!

    init(
        state: any(
            ChatConversationSelectionAccess &
                ChatStreamingProjectionAccess &
                ChatReplyFeedbackAccess
        ),
        services: any(
            ChatPersistenceAccess &
                ChatTransportServiceAccess &
                ChatGeneratedFileServiceAccess &
                ChatRuntimeRegistryAccess
        )
    ) {
        self.state = state
        self.services = services
    }

    @discardableResult
    func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ReplySession,
        visible: Bool
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error, statusCode == 404 else {
            return false
        }

        let fallbackText: String
        if message.usedBackgroundMode {
            if visible {
                state.errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                state.errorMessage = nil
            }
            fallbackText = interruptedResponseFallbackText(for: message, session: session)
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        finishRecovery(
            for: message,
            session: session,
            result: nil,
            fallbackText: fallbackText,
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
        )
        return true
    }

    func recoveryFallbackText(for message: Message, session: ReplySession? = nil) -> String {
        if let session,
           let runtimeState = sessions.cachedRuntimeState(for: session),
           !runtimeState.buffer.text.isEmpty {
            return runtimeState.buffer.text
        }
        if message.id == sessions.visibleSessionMessageID, !state.currentStreamingText.isEmpty {
            return state.currentStreamingText
        }
        return message.content
    }

    func recoveryFallbackThinking(for message: Message, session: ReplySession? = nil) -> String? {
        if let session,
           let runtimeState = sessions.cachedRuntimeState(for: session),
           !runtimeState.buffer.thinking.isEmpty {
            return runtimeState.buffer.thinking
        }
        if message.id == sessions.visibleSessionMessageID, !state.currentThinkingText.isEmpty {
            return state.currentThinkingText
        }
        return message.thinking
    }

    func interruptedResponseFallbackText(for message: Message, session: ReplySession? = nil) -> String {
        let interruptionNotice = "Response interrupted because the app was closed before completion."
        let baseText = recoveryFallbackText(for: message, session: session)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseText.isEmpty else {
            return interruptionNotice
        }

        if baseText.contains(interruptionNotice) {
            return baseText
        }

        return "\(baseText)\n\n\(interruptionNotice)"
    }

    func activeAPIKey(for session: ReplySession) -> String {
        let key = session.request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? storedKey : key
    }

    func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        services.messagePersistence.applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )
    }

    func finishRecovery(
        for message: Message,
        session: ReplySession,
        result: OpenAIResponseFetchResult?,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )

        conversations.saveContextIfPossible("finishRecovery")
        conversations.upsertMessage(message)
        files.prefetchGeneratedFilesIfNeeded(for: message)

        let conversation = message.conversation
        let wasVisible = sessions.visibleSessionMessageID == session.messageID
        sessions.removeSession(session)

        if let conversation {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let apiKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                await generateConversationTitleIfNeeded(
                    for: conversation,
                    apiKey: apiKey,
                    openAIService: services.openAIService,
                    saveContext: { self.conversations.saveContextIfPossible($0) }
                )
            }
        }

        if wasVisible {
            state.hapticService.notify(.success, isEnabled: state.hapticsEnabled)
        }
    }
}
