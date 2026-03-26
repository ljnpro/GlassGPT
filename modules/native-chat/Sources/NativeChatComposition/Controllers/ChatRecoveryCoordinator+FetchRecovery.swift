import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    func startRecoveryFetchTask(
        execution: SessionExecutionState,
        message: Message,
        session: ReplySession,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool
    ) {
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { execution.task = nil }
            guard sessions.isSessionActive(session) else { return }
            let apiKey = resultApplier.activeAPIKey(for: session)
            let fetchOutcome = await makeRecoveryFetchOutcome(
                execution: execution,
                responseId: responseId,
                apiKey: apiKey,
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: message.usedBackgroundMode,
                lastSequenceNumber: message.lastSequenceNumber
            )
            await handleRecoveryFetchOutcome(
                fetchOutcome,
                for: message,
                session: session,
                responseId: responseId,
                apiKey: apiKey,
                visible: visible
            )
        }
    }

    func restartRecoveryIfUnrecoverable(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ReplySession,
        visible: Bool
    ) async -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error, statusCode == 404 else {
            return false
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        return await restartMessageAfterRecoveryExhausted(
            message,
            session: session,
            visible: visible,
            errorMessage: message.usedBackgroundMode ? "This response is no longer resumable." : nil
        )
    }

    func makeRecoveryFetchOutcome(
        execution: SessionExecutionState,
        responseId: String,
        apiKey: String,
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) async -> RecoveryFetchOutcome {
        do {
            let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: apiKey)
            execution.markProgress()
            return RecoveryFetchOutcome(
                result: result,
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: usedBackgroundMode,
                lastSequenceNumber: lastSequenceNumber
            )
        } catch {
            return RecoveryFetchOutcome(
                error: error,
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: usedBackgroundMode,
                lastSequenceNumber: lastSequenceNumber
            )
        }
    }

    func handleRecoveryFetchOutcome(
        _ fetchOutcome: RecoveryFetchOutcome,
        for message: Message,
        session: ReplySession,
        responseId: String,
        apiKey: String,
        visible: Bool
    ) async {
        let action = RecoveryFetchEvaluator.evaluate(fetchOutcome)

        switch action {
        case let .finish(result, errorMessage):
            if result.status == .completed {
                if visible, let errorMessage {
                    state.errorMessage = errorMessage
                }
                resultApplier.finishRecovery(
                    for: message,
                    session: session,
                    result: result,
                    fallbackText: resultApplier.recoveryFallbackText(for: message, session: session),
                    fallbackThinking: resultApplier.recoveryFallbackThinking(for: message, session: session)
                )
            } else {
                _ = await restartMessageAfterRecoveryExhausted(
                    message,
                    session: session,
                    visible: visible,
                    errorMessage: errorMessage
                )
            }

        case let .startStream(lastSequenceNumber):
            await startStreamingRecovery(
                session: session,
                responseId: responseId,
                lastSeq: lastSequenceNumber,
                apiKey: apiKey,
                useDirectEndpoint: false
            )

        case .poll:
            await pollResponseUntilTerminal(session: session, responseId: responseId)

        case let .handleError(error):
            if await restartRecoveryIfUnrecoverable(
                error,
                for: message,
                responseId: responseId,
                session: session,
                visible: visible
            ) {
                return
            }
            await pollResponseUntilTerminal(session: session, responseId: responseId)
        }
    }
}
