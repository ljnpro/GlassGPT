import Foundation

@MainActor
extension ChatScreenStore {

    // MARK: - Recovery

    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        conversationRuntime.recoveryCoordinator.recoverResponse(
            messageId: messageId,
            responseId: responseId,
            preferStreamingResume: preferStreamingResume,
            visible: visible
        )
    }

    func startStreamingRecovery(
        session: ResponseSession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        await conversationRuntime.recoveryCoordinator.startStreamingRecovery(
            session: session,
            responseId: responseId,
            lastSeq: lastSeq,
            apiKey: apiKey,
            useDirectEndpoint: useDirectEndpoint
        )
    }

    func pollResponseUntilTerminal(session: ResponseSession, responseId: String) async {
        await conversationRuntime.recoveryCoordinator.pollResponseUntilTerminal(
            session: session,
            responseId: responseId
        )
    }

    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        await conversationRuntime.recoveryCoordinator.cancelBackgroundResponseAndSync(
            responseId: responseId,
            messageId: messageId
        )
    }

    @discardableResult
    func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ResponseSession,
        visible: Bool
    ) -> Bool {
        conversationRuntime.recoveryCoordinator.handleUnrecoverableRecoveryError(
            error,
            for: message,
            responseId: responseId,
            session: session,
            visible: visible
        )
    }

    func recoveryFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        conversationRuntime.recoveryCoordinator.recoveryFallbackText(for: message, session: session)
    }

    func recoveryFallbackThinking(for message: Message, session: ResponseSession? = nil) -> String? {
        conversationRuntime.recoveryCoordinator.recoveryFallbackThinking(for: message, session: session)
    }

    func interruptedResponseFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        conversationRuntime.recoveryCoordinator.interruptedResponseFallbackText(for: message, session: session)
    }
}
